import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Key-value storage used for the anonymous id and the results cache.
/// The default is [SharedPreferencesFlagsStorage]; pass your own to
/// [RiviumFlags.init] if you need a different store.
abstract class RiviumFlagsStorage {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

/// Default storage, backed by `shared_preferences`.
class SharedPreferencesFlagsStorage implements RiviumFlagsStorage {
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<String?> getString(String key) async => (await _p).getString(key);

  @override
  Future<void> setString(String key, String value) async =>
      (await _p).setString(key, value);

  @override
  Future<void> remove(String key) async => (await _p).remove(key);
}

/// In-memory storage: nothing survives a restart. Useful in tests.
class MemoryFlagsStorage implements RiviumFlagsStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

/// Storage keys.
abstract final class FlagsStorageKeys {
  static const anonymousId = 'rivium_flags_anonymous_id';
  static const cache = 'rivium_flags_cache_v2';

  /// 0.1.x keys, removed on first start of 0.2.0.
  static const legacy = ['rivium_ff_cached_flags', 'rivium_ff_user_id'];
}

final _uuidRegExp = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

/// True when [s] is a lowercase, hyphenated UUID v4.
bool isUuidV4(String s) => _uuidRegExp.hasMatch(s);

/// A random UUID v4, lowercase and hyphenated.
String generateUuidV4([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
