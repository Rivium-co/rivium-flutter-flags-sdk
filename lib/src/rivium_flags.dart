import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';
import 'storage.dart';

/// Rivium Flags client for Flutter.
///
/// Flags are evaluated on the Rivium server (`POST /public/v2/evaluate`);
/// the app only stores the results, so no targeting rules ever reach the
/// device. Getters are synchronous and read the stored results.
///
/// ```dart
/// final flags = await RiviumFlags.init(
///   const RiviumFlagsConfig(apiKey: 'rv_live_xxx', environment: 'production'),
/// );
/// await flags.identify('user-123', attributes: {'plan': 'pro'});
/// if (flags.isEnabled('new-checkout')) { … }
/// final theme = flags.getString('theme', 'light');
/// ```
class RiviumFlags with WidgetsBindingObserver {
  /// SDK version, sent as `x-rivium-sdk: flutter/<version>`.
  static const sdkVersion = '0.2.1';

  static const _debounce = Duration(milliseconds: 250);
  static const _foregroundStaleAfter = Duration(minutes: 15);
  static const _requestTimeout = Duration(seconds: 30);
  static const _maxBackoffSeconds = 300;

  static RiviumFlags? _instance;

  /// The client created by [init]. Throws if [init] was not called.
  static RiviumFlags get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('Rivium Flags: call RiviumFlags.init() first');
    }
    return i;
  }

  final RiviumFlagsConfig config;
  final RiviumFlagsStorage _storage;
  final http.Client _http;
  final bool _ownsHttp;
  final Random _random;

  late String _anonymousId;
  String? _userId;
  Map<String, Object?> _attributes;

  Map<String, RiviumFlagResult>? _flags;
  String? _etag;
  String? _cachedRequestKey;
  String? _environment;
  DateTime? _lastSuccessAt;

  final _changes = StreamController<void>.broadcast();
  final _errors = StreamController<RiviumFlagsError>.broadcast();
  final _ready = Completer<void>();
  RiviumFlagsError? _lastError;
  int? _lastLoggedStatus;

  int _generation = 0;
  Future<void>? _inFlight;
  String? _inFlightKey;
  int _inFlightGen = -1;
  Timer? _debounceTimer;
  List<Completer<void>> _debounceWaiters = [];
  Timer? _retryTimer;
  Timer? _pollTimer;
  int _failureCount = 0;
  DateTime? _blockedUntil;
  Duration? _lastRetryDelay;
  bool _halted = false;
  String? _rejectedBody;
  bool _foreground = true;
  bool _observing = false;
  bool _closed = false;

  RiviumFlags._(
    this.config, {
    required RiviumFlagsStorage storage,
    http.Client? httpClient,
    Random? random,
  })  : _storage = storage,
        _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null,
        _random = random ?? Random(),
        _userId = _nonEmpty(config.userId),
        _attributes = Map.of(config.attributes);

  /// Creates the shared client ([instance]), serves the cached results right
  /// away and waits up to [RiviumFlagsConfig.initTimeout] for the first
  /// network answer. Calling it again closes the previous client.
  static Future<RiviumFlags> init(
    RiviumFlagsConfig config, {
    RiviumFlagsStorage? storage,
    http.Client? httpClient,
    bool observeAppLifecycle = true,
  }) async {
    final previous = _instance;
    if (previous != null && !previous._closed) previous.close();
    final client = await create(config,
        storage: storage,
        httpClient: httpClient,
        observeAppLifecycle: observeAppLifecycle);
    _instance = client;
    return client;
  }

  /// Like [init] but does not touch [instance] (for several clients, or tests).
  static Future<RiviumFlags> create(
    RiviumFlagsConfig config, {
    RiviumFlagsStorage? storage,
    http.Client? httpClient,
    bool observeAppLifecycle = true,
    @visibleForTesting Random? random,
  }) async {
    if (config.apiKey.isEmpty) {
      throw ArgumentError('Rivium Flags: apiKey is required');
    }
    if (config.apiKey.startsWith('rv_srv_')) {
      throw ArgumentError(
          'Rivium Flags: that is a server secret. Apps use the public key (rv_live_… / rv_test_…).');
    }
    final client = RiviumFlags._(config,
        storage: storage ?? SharedPreferencesFlagsStorage(),
        httpClient: httpClient,
        random: random);
    await client._start(observeAppLifecycle);
    return client;
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// The install's anonymous id (UUID v4). Survives [reset].
  String get anonymousId => _anonymousId;

  /// The signed-in user id, or `null`.
  String? get userId => _userId;

  /// The current targeting attributes.
  Map<String, Object?> get attributes => Map.unmodifiable(_attributes);

  /// True once results are available (from the cache or the network).
  bool get isReady => _flags != null;

  /// Completes the first time results are available (cache or network).
  Future<void> get whenReady => _ready.future;

  /// Emits whenever the stored results change.
  Stream<void> get onChange => _changes.stream;

  /// Emits request failures (status, server `code`, message).
  Stream<RiviumFlagsError> get onError => _errors.stream;

  /// The last request failure, cleared by the next success.
  RiviumFlagsError? get lastError => _lastError;

  /// When the last successful (200 or 304) answer arrived.
  DateTime? get lastFetchedAt => _lastSuccessAt;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  /// The flag's `enabled` (true only for reasons `ON` / `VARIANT`), or
  /// [defaultValue] when the flag is unknown or results are not ready.
  bool isEnabled(String key, [bool defaultValue = false]) {
    final r = _flags?[key];
    return r == null ? defaultValue : r.enabled;
  }

  /// Value of a `boolean` flag.
  bool getBool(String key, bool defaultValue) =>
      getBoolDetail(key, defaultValue).value;

  /// Value of a `string` flag.
  String getString(String key, String defaultValue) =>
      getStringDetail(key, defaultValue).value;

  /// Value of a `number` flag.
  num getNumber(String key, num defaultValue) =>
      getNumberDetail(key, defaultValue).value;

  /// Value of a `json` flag (any JSON value: map, list, string, number, bool, null).
  Object? getJson(String key, Object? defaultValue) =>
      getJsonDetail(key, defaultValue).value;

  RiviumFlagDetail<bool> getBoolDetail(String key, bool defaultValue) =>
      _typed<bool>(key, defaultValue, 'boolean', (v) => v is bool);

  RiviumFlagDetail<String> getStringDetail(String key, String defaultValue) =>
      _typed<String>(key, defaultValue, 'string', (v) => v is String);

  RiviumFlagDetail<num> getNumberDetail(String key, num defaultValue) =>
      _typed<num>(key, defaultValue, 'number', (v) => v is num);

  RiviumFlagDetail<Object?> getJsonDetail(String key, Object? defaultValue) =>
      _typed<Object?>(key, defaultValue, 'json', (_) => true);

  /// The stored result for [key] without a type check; [defaultValue] when
  /// it is unknown (`FLAG_NOT_FOUND`) or not ready (`NOT_READY`).
  RiviumFlagDetail<Object?> getDetail(String key, [Object? defaultValue]) {
    final flags = _flags;
    if (flags == null) return _fallback(defaultValue, RiviumFlagReason.notReady);
    final r = flags[key];
    if (r == null) return _fallback(defaultValue, RiviumFlagReason.flagNotFound);
    return RiviumFlagDetail(
        value: r.value,
        enabled: r.enabled,
        variant: r.variant,
        reason: r.reason,
        version: r.version);
  }

  /// Every stored result, by flag key (empty when not ready).
  Map<String, RiviumFlagResult> getAll() => Map.unmodifiable(_flags ?? const {});

  RiviumFlagDetail<T> _typed<T>(
      String key, T defaultValue, String type, bool Function(Object?) ok) {
    final flags = _flags;
    if (flags == null) return _fallback(defaultValue, RiviumFlagReason.notReady);
    final r = flags[key];
    if (r == null) return _fallback(defaultValue, RiviumFlagReason.flagNotFound);
    if (r.valueType != type || !ok(r.value)) {
      return RiviumFlagDetail(
          value: defaultValue,
          enabled: false,
          variant: null,
          reason: RiviumFlagReason.typeMismatch,
          version: r.version);
    }
    return RiviumFlagDetail(
        value: r.value as T,
        enabled: r.enabled,
        variant: r.variant,
        reason: r.reason,
        version: r.version);
  }

  static RiviumFlagDetail<T> _fallback<T>(T value, String reason) =>
      RiviumFlagDetail(value: value, enabled: false, variant: null, reason: reason);

  // ---------------------------------------------------------------------------
  // Context
  // ---------------------------------------------------------------------------

  /// Sets the signed-in user and (when given) replaces the attributes, then
  /// fetches (debounced 250 ms). Results of the previous user are dropped.
  ///
  /// Sends no request when the user and the attributes are the same as before
  /// and the results for them are already here (or on their way).
  Future<void> identify(String? userId, {Map<String, Object?>? attributes}) {
    _ensureOpen();
    final before = _requestKey();
    _setUser(userId);
    if (attributes != null) _attributes = Map.of(attributes);
    return _contextChanged(before);
  }

  /// Sets or clears the signed-in user id, then fetches (debounced) if it
  /// is another user.
  Future<void> setUserId(String? userId) {
    _ensureOpen();
    final before = _requestKey();
    _setUser(userId);
    return _contextChanged(before);
  }

  /// Replaces the targeting attributes, then fetches (debounced) if their
  /// content changed.
  Future<void> setAttributes(Map<String, Object?> attributes) {
    _ensureOpen();
    final before = _requestKey();
    _attributes = Map.of(attributes);
    return _contextChanged(before);
  }

  /// Sign-out: clears the user id, the attributes and the stored results,
  /// keeps the anonymous id, and fetches for the anonymous context.
  Future<void> reset() async {
    _ensureOpen();
    _userId = null;
    _attributes = {};
    await _dropResults();
    _cancelDebounce();
    return _fetch();
  }

  /// Generates a new anonymous id (explicit; [reset] keeps it) and fetches.
  Future<void> resetAnonymousId() async {
    _ensureOpen();
    _anonymousId = generateUuidV4();
    await _storage.setString(FlagsStorageKeys.anonymousId, _anonymousId);
    if (_userId == null) await _dropResults();
    _cancelDebounce();
    return _fetch();
  }

  /// Fetches now. Also resumes after a 401 / 403 / 404 stopped automatic
  /// fetches. During a 429 back-off it waits for `Retry-After`.
  Future<void> refresh() {
    _ensureOpen();
    _halted = false;
    _rejectedBody = null;
    _cancelDebounce();
    return _fetch();
  }

  /// Stops timers and the lifecycle observer and releases the HTTP client.
  void close() {
    if (_closed) return;
    _closed = true;
    _generation++;
    _cancelDebounce();
    _retryTimer?.cancel();
    _pollTimer?.cancel();
    if (_observing) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
    }
    if (_ownsHttp) _http.close();
    _changes.close();
    _errors.close();
    if (identical(_instance, this)) _instance = null;
  }

  // ---------------------------------------------------------------------------
  // App lifecycle
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onForeground();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      onBackground();
    }
  }

  /// Called on app resume (automatic when lifecycle observing is on): fetches
  /// if the last success is older than 15 minutes and resumes polling.
  @visibleForTesting
  void onForeground() {
    if (_closed) return;
    _foreground = true;
    _startPolling();
    final last = _lastSuccessAt;
    if (!_halted &&
        (last == null || DateTime.now().difference(last) > _foregroundStaleAfter)) {
      _fetch();
    }
  }

  /// Called when the app goes to the background: polling pauses.
  @visibleForTesting
  void onBackground() {
    _foreground = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// The delay of the last scheduled automatic retry (429 / 5xx / network).
  @visibleForTesting
  Duration? get lastRetryDelay => _lastRetryDelay;

  /// True after 401 / 403 / 404 until [refresh].
  @visibleForTesting
  bool get isHalted => _halted;

  Future<void> _start(bool observeLifecycle) async {
    // Anonymous id.
    String? anon;
    try {
      anon = await _storage.getString(FlagsStorageKeys.anonymousId);
    } catch (_) {}
    if (anon == null || anon.isEmpty) {
      anon = generateUuidV4();
      try {
        await _storage.setString(FlagsStorageKeys.anonymousId, anon);
      } catch (_) {}
    }
    _anonymousId = anon;

    // 0.1.x leftovers.
    for (final k in FlagsStorageKeys.legacy) {
      try {
        await _storage.remove(k);
      } catch (_) {}
    }

    await _loadCache();

    if (observeLifecycle) {
      try {
        WidgetsBinding.instance.addObserver(this);
        _observing = true;
      } catch (_) {
        _log('lifecycle observer unavailable (call WidgetsFlutterBinding.ensureInitialized() first)');
      }
    }
    _startPolling();

    final first = _fetch();
    try {
      await first.timeout(config.initTimeout);
    } on TimeoutException {
      _log('first fetch is slow; serving ${isReady ? 'cached results' : 'code defaults'} meanwhile');
    }
  }

  Future<void> _loadCache() async {
    try {
      final raw = await _storage.getString(FlagsStorageKeys.cache);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['userId'] != _userId) {
        await _storage.remove(FlagsStorageKeys.cache);
        return;
      }
      _flags = _parseFlags(data['flags']);
      _etag = data['etag'] as String?;
      _cachedRequestKey = data['requestKey'] as String?;
      _environment = data['environment'] as String?;
      final at = data['fetchedAt'] as String?;
      _lastSuccessAt = at == null ? null : DateTime.tryParse(at);
      _markReady();
      _changes.add(null);
      _log('serving ${_flags!.length} cached results');
    } catch (_) {
      // A broken cache is ignored.
    }
  }

  Future<void> _saveCache() async {
    final flags = _flags;
    if (flags == null) return;
    try {
      await _storage.setString(
          FlagsStorageKeys.cache,
          jsonEncode({
            'flags': flags.map((k, v) => MapEntry(k, v.toJson())),
            'etag': _etag,
            'requestKey': _cachedRequestKey,
            'environment': _environment,
            'userId': _userId,
            'fetchedAt': _lastSuccessAt?.toIso8601String(),
          }));
    } catch (_) {}
  }

  Future<void> _dropResults() async {
    _generation++; // an answer for the old context must not land
    final had = _flags != null;
    _flags = null;
    _etag = null;
    _cachedRequestKey = null;
    try {
      await _storage.remove(FlagsStorageKeys.cache);
    } catch (_) {}
    if (had && !_changes.isClosed) _changes.add(null);
  }

  void _setUser(String? userId) {
    _ensureOpen();
    final next = _nonEmpty(userId);
    if (next != _userId) {
      _userId = next;
      _dropResults();
    }
  }

  /// The current request as a string (equal contexts give equal strings), or
  /// `null` when it cannot be encoded.
  String? _requestKey() {
    try {
      return _canonicalJson(buildRequestBody());
    } catch (_) {
      return null;
    }
  }

  /// True when the stored results were fetched for exactly this request.
  bool _hasResultsFor(String? key) =>
      key != null && _flags != null && _cachedRequestKey == key;

  /// Called after identify / setUserId / setAttributes; [before] is the
  /// request key from before the call.
  Future<void> _contextChanged(String? before) {
    _ensureOpen();
    final key = _requestKey();
    if (key != null && key == before) {
      // Same user and attributes: never a second request for them.
      if (_debounceTimer != null) {
        final waiter = Completer<void>();
        _debounceWaiters.add(waiter);
        return waiter.future;
      }
      final running = _inFlight;
      if (running != null && _inFlightKey == key && _inFlightGen == _generation) {
        return running;
      }
      if (_hasResultsFor(key)) return Future.value();
    }
    _generation++;
    final waiter = Completer<void>();
    _debounceWaiters.add(waiter);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      final waiters = _debounceWaiters;
      _debounceWaiters = [];
      _debounceTimer = null;
      // Changed and changed back: the results for this context are still here.
      final next = _hasResultsFor(_requestKey()) ? Future<void>.value() : _fetch();
      next.whenComplete(() {
        for (final w in waiters) {
          if (!w.isCompleted) w.complete();
        }
      });
    });
    return waiter.future;
  }

  void _cancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final waiters = _debounceWaiters;
    _debounceWaiters = [];
    for (final w in waiters) {
      if (!w.isCompleted) w.complete();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    final s = config.refreshIntervalSeconds;
    if (s <= 0 || !_foreground || _closed) return;
    _pollTimer = Timer.periodic(Duration(seconds: max(60, s)), (_) {
      if (_foreground && !_halted) _fetch();
    });
  }

  /// The JSON body of the next evaluate request.
  @visibleForTesting
  Map<String, Object?> buildRequestBody() => {
        if (config.environment != null) 'environment': config.environment,
        'context': {
          if (_userId != null) 'userId': _userId,
          'anonymousId': _anonymousId,
          'attributes': _attributes,
        },
        if (config.flagKeys != null) 'flagKeys': config.flagKeys,
      };

  Future<void> _fetch() {
    if (_closed) return Future.value();
    final body = buildRequestBody();
    final key = _canonicalJson(body);
    final running = _inFlight;
    if (running != null && _inFlightKey == key && _inFlightGen == _generation) {
      return running;
    }

    final blocked = _blockedUntil;
    if (blocked != null && DateTime.now().isBefore(blocked)) {
      _scheduleRetry(blocked.difference(DateTime.now()));
      return Future.value();
    }
    if (_rejectedBody == key) return Future.value();

    final gen = ++_generation;
    final future = _send(body, key, gen);
    _inFlight = future;
    _inFlightKey = key;
    _inFlightGen = gen;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
        _inFlightKey = null;
      }
    });
  }

  Future<void> _send(Map<String, Object?> body, String key, int gen) async {
    final headers = <String, String>{
      'content-type': 'application/json',
      'x-api-key': config.apiKey,
      'x-rivium-sdk': 'flutter/$sdkVersion',
    };
    final etag = _etag;
    if (etag != null && _flags != null && _cachedRequestKey == key) {
      headers['if-none-match'] = etag;
    }

    http.Response res;
    try {
      res = await _http
          .post(Uri.parse('${_trimSlash(config.baseUrl)}/public/v2/evaluate'),
              headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);
    } catch (e) {
      if (gen != _generation || _closed) return;
      _fail(null, null, 'network error: $e', retry: true);
      return;
    }
    if (gen != _generation || _closed) return; // superseded by a newer context

    final status = res.statusCode;
    if (status == 200) {
      Map<String, RiviumFlagResult> flags;
      String? environment;
      try {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        flags = _parseFlags(data['flags']);
        environment = data['environment'] as String?;
      } catch (e) {
        _fail(status, null, 'unreadable response: $e', retry: true);
        return;
      }
      _flags = flags;
      _etag = res.headers['etag'];
      _cachedRequestKey = key;
      _environment = environment;
      _succeeded();
      _changes.add(null);
      await _saveCache();
      _log('fetched ${flags.length} flags');
      return;
    }
    if (status == 304) {
      _succeeded();
      await _saveCache();
      _log('results unchanged (304)');
      return;
    }

    String? code;
    String message = 'HTTP $status';
    try {
      final err = jsonDecode(res.body);
      if (err is Map) {
        code = err['code'] as String?;
        final m = err['message'];
        if (m is String) message = m;
        if (m is List) message = m.join('; ');
      }
    } catch (_) {}

    if (status == 429) {
      final ra = int.tryParse(res.headers['retry-after'] ?? '');
      _fail(status, code, message, retry: true, retryAfterSeconds: ra ?? 5);
    } else if (status >= 500) {
      _fail(status, code, message, retry: true);
    } else if (status == 401 || status == 403 || status == 404) {
      _halted = true;
      _fail(status, code, message, retry: false);
    } else {
      // 400 / 413 / other 4xx: do not resend the same body.
      _rejectedBody = key;
      _fail(status, code, message, retry: false);
    }
  }

  void _succeeded() {
    _lastSuccessAt = DateTime.now();
    _failureCount = 0;
    _blockedUntil = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _lastError = null;
    _lastLoggedStatus = null;
    _markReady();
  }

  void _fail(int? status, String? code, String message,
      {required bool retry, int? retryAfterSeconds}) {
    final error = RiviumFlagsError(statusCode: status, code: code, message: message);
    _lastError = error;
    if (!_errors.isClosed) _errors.add(error);
    final logKey = status ?? -1;
    if (_lastLoggedStatus != logKey) {
      _lastLoggedStatus = logKey;
      _log('request failed: $error${_flags != null ? ' (serving cached results)' : ''}',
          error: true);
    }
    if (!retry) return;
    _failureCount++;
    final base = retryAfterSeconds ?? 5;
    final exp = min(_maxBackoffSeconds, base * pow(2, _failureCount - 1)).toDouble();
    final jitter = 0.8 + _random.nextDouble() * 0.4;
    var seconds = exp * jitter;
    if (retryAfterSeconds != null) {
      seconds = max(seconds, retryAfterSeconds.toDouble()); // never earlier than Retry-After
      _blockedUntil = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
    }
    _scheduleRetry(Duration(milliseconds: (seconds * 1000).round()));
  }

  void _scheduleRetry(Duration delay) {
    if (_closed) return;
    _lastRetryDelay = delay;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!_halted) _fetch();
    });
  }

  void _markReady() {
    if (!_ready.isCompleted) _ready.complete();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Rivium Flags: this client is closed');
  }

  void _log(String message, {bool error = false}) {
    if (error || config.debug) debugPrint('[Rivium Flags] $message');
  }

  static Map<String, RiviumFlagResult> _parseFlags(Object? raw) {
    final out = <String, RiviumFlagResult>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v is Map) {
          out[k] = RiviumFlagResult.fromJson(k, Map<String, dynamic>.from(v));
        }
      });
    }
    return out;
  }

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

  static String _trimSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  /// JSON with sorted object keys, so equal contexts give equal strings.
  static String _canonicalJson(Object? v) => jsonEncode(_sortKeys(v));

  static Object? _sortKeys(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: _sortKeys(v[k])};
    }
    if (v is List) return v.map(_sortKeys).toList();
    return v;
  }
}
