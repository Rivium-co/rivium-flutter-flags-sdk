import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rivium_flutter_flags/rivium_flutter_flags.dart';
import 'package:rivium_flutter_flags/src/storage.dart' show isUuidV4, generateUuidV4;

const _key = 'rv_test_key';

/// A fake `POST /public/v2/evaluate`. [handler] decides each answer.
class FakeServer {
  final List<http.Request> requests = [];
  http.Response Function(http.Request req, Map<String, dynamic> body) handler;

  FakeServer(this.handler);

  MockClient get client => MockClient((req) async {
        requests.add(req);
        return handler(req, jsonDecode(req.body) as Map<String, dynamic>);
      });

  Map<String, dynamic> body(int i) =>
      jsonDecode(requests[i].body) as Map<String, dynamic>;
}

http.Response ok(Map<String, Map<String, dynamic>> flags,
        {String etag = '"e2-abc"', String? environment}) =>
    http.Response(
        jsonEncode({
          'environment': environment,
          'evaluatedAt': '2026-10-01T12:00:00.000Z',
          'flags': flags,
        }),
        200,
        headers: {'etag': etag, 'content-type': 'application/json'});

Map<String, dynamic> flag(String key, String type, Object? value,
        {bool enabled = true, String? variant, String reason = 'ON', int version = 1}) =>
    {
      'key': key,
      'valueType': type,
      'enabled': enabled,
      'value': value,
      'variant': variant,
      'reason': reason,
      'version': version,
    };

Future<RiviumFlags> make(FakeServer server,
        {RiviumFlagsConfig? config, MemoryFlagsStorage? storage}) =>
    RiviumFlags.create(config ?? const RiviumFlagsConfig(apiKey: _key),
        storage: storage ?? MemoryFlagsStorage(),
        httpClient: server.client,
        observeAppLifecycle: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final vectors = jsonDecode(
          File('test/fixtures/sdk-test-vectors.json').readAsStringSync())
      as Map<String, dynamic>;

  group('contract test vectors (client side: request, parsing, getters)', () {
    var total = 0;
    for (final suite in (vectors['suites'] as List).cast<Map<String, dynamic>>()) {
      final flagDefs = {
        for (final f in (suite['flags'] as List).cast<Map<String, dynamic>>())
          f['key'] as String: f
      };
      for (final c in (suite['cases'] as List).cast<Map<String, dynamic>>()) {
        total++;
        test('${suite['name']}: ${c['name']}', () async {
          final flagKey = c['flagKey'] as String;
          final ctx = Map<String, dynamic>.from(c['context'] as Map);
          final expected = Map<String, dynamic>.from(c['expected'] as Map);
          final def = flagDefs[flagKey];
          final valueType = (def?['valueType'] as String?) ?? 'boolean';

          // The server answers with the case's expected result (as the backend
          // engine produced it); a missing flag is simply absent.
          final server = FakeServer((req, body) => ok({
                if (def != null)
                  flagKey: {
                    'key': flagKey,
                    'valueType': valueType,
                    ...expected,
                    'version': def['version'],
                  }
              }));
          final attrs = Map<String, Object?>.from((ctx['attributes'] as Map?) ?? {});
          final client = await make(server,
              config: RiviumFlagsConfig(
                  apiKey: _key,
                  environment: 'production',
                  flagKeys: [flagKey],
                  userId: ctx['userId'] as String?,
                  attributes: attrs));

          // Request shape.
          expect(server.requests, hasLength(1));
          final req = server.requests.single;
          expect(req.method, 'POST');
          expect(req.url.toString(), 'https://flags.rivium.co/public/v2/evaluate');
          expect(req.headers['x-api-key'], _key);
          expect(req.headers['x-rivium-sdk'], 'flutter/${RiviumFlags.sdkVersion}');
          expect(req.headers.containsKey('x-server-secret'), isFalse);
          final body = server.body(0);
          expect(body['environment'], 'production');
          expect(body['flagKeys'], [flagKey]);
          final sent = body['context'] as Map<String, dynamic>;
          // An empty userId is "signed out": the SDK omits it (the server
          // requires 1–256 chars).
          final uid = ctx['userId'] as String?;
          if (uid != null && uid.isNotEmpty) {
            expect(sent['userId'], uid);
          } else {
            expect(sent.containsKey('userId'), isFalse);
          }
          expect(isUuidV4(sent['anonymousId'] as String), isTrue);
          expect(sent['attributes'], attrs);

          // Parsing + getters.
          final d = client.getDetail(flagKey, '__default__');
          if (def == null) {
            expect(d.reason, RiviumFlagReason.flagNotFound);
            expect(d.value, '__default__');
            expect(d.enabled, isFalse);
          } else {
            expect(d.enabled, expected['enabled']);
            expect(d.value, equals(expected['value']));
            expect(d.variant, expected['variant']);
            expect(d.reason, expected['reason']);
            expect(client.isEnabled(flagKey, !(expected['enabled'] as bool)),
                expected['enabled']);

            // The getter matching the type returns the value; another one
            // returns the code default with TYPE_MISMATCH.
            switch (valueType) {
              case 'boolean':
                expect(client.getBool(flagKey, !(expected['value'] as bool)), expected['value']);
                final m = client.getStringDetail(flagKey, 'dflt');
                expect([m.value, m.reason], ['dflt', RiviumFlagReason.typeMismatch]);
              case 'string':
                expect(client.getString(flagKey, '__x__'), expected['value']);
                final m = client.getBoolDetail(flagKey, true);
                expect([m.value, m.reason], [true, RiviumFlagReason.typeMismatch]);
              case 'number':
                expect(client.getNumber(flagKey, -12345), expected['value']);
                final m = client.getJsonDetail(flagKey, null);
                expect(m.reason, RiviumFlagReason.typeMismatch);
              case 'json':
                expect(client.getJson(flagKey, '__x__'), equals(expected['value']));
                final m = client.getNumberDetail(flagKey, 7);
                expect([m.value, m.reason], [7, RiviumFlagReason.typeMismatch]);
            }
          }
          client.close();
        });
      }
    }
    test('vector count', () => expect(total, 171));
  });

  group('anonymous id', () {
    test('generated once as UUID v4 and persisted under its fixed key', () async {
      final storage = MemoryFlagsStorage();
      final server = FakeServer((_, __) => ok({}));
      final a = await make(server, storage: storage);
      expect(isUuidV4(a.anonymousId), isTrue);
      expect(storage.values['rivium_flags_anonymous_id'], a.anonymousId);
      a.close();
      final b = await make(server, storage: storage);
      expect(b.anonymousId, a.anonymousId);
      b.close();
    });

    test('sent with a userId too; reset() keeps it; resetAnonymousId() replaces it', () async {
      final server = FakeServer((_, __) => ok({}));
      final c = await make(server);
      final first = c.anonymousId;
      await c.identify('u1');
      expect((server.body(1)['context'] as Map)['anonymousId'], first);
      expect((server.body(1)['context'] as Map)['userId'], 'u1');
      await c.reset();
      expect(c.anonymousId, first);
      expect(c.userId, isNull);
      await c.resetAnonymousId();
      expect(c.anonymousId, isNot(first));
      expect(isUuidV4(c.anonymousId), isTrue);
      c.close();
    });

    test('UUID generator', () {
      final ids = {for (var i = 0; i < 200; i++) generateUuidV4()};
      expect(ids, hasLength(200));
      expect(ids.every(isUuidV4), isTrue);
    });

    test('0.1.x storage keys are removed', () async {
      final storage = MemoryFlagsStorage()
        ..values['rivium_ff_cached_flags'] = '[]'
        ..values['rivium_ff_user_id'] = 'x';
      final c = await make(FakeServer((_, __) => ok({})), storage: storage);
      expect(storage.values.containsKey('rivium_ff_cached_flags'), isFalse);
      expect(storage.values.containsKey('rivium_ff_user_id'), isFalse);
      c.close();
    });
  });

  group('readiness and reasons', () {
    test('NOT_READY before any result, FLAG_NOT_FOUND after', () async {
      final gate = Completer<void>();
      final server = FakeServer((_, __) => ok({'a': flag('a', 'boolean', true)}));
      final client = MockClient((req) async {
        await gate.future;
        return server.handler(req, jsonDecode(req.body));
      });
      final c = await RiviumFlags.create(
          const RiviumFlagsConfig(apiKey: _key, initTimeout: Duration(milliseconds: 10)),
          storage: MemoryFlagsStorage(),
          httpClient: client,
          observeAppLifecycle: false);
      expect(c.isReady, isFalse);
      expect(c.getBoolDetail('a', false).reason, RiviumFlagReason.notReady);
      expect(c.isEnabled('a', true), isTrue); // code default
      gate.complete();
      await c.whenReady;
      expect(c.getBool('a', false), isTrue);
      expect(c.getDetail('zzz', 1).reason, RiviumFlagReason.flagNotFound);
      expect(c.getDetail('zzz', 1).value, 1);
      c.close();
    });

    test('rejects a server secret', () async {
      expect(
          () => RiviumFlags.create(const RiviumFlagsConfig(apiKey: 'rv_srv_x'),
              storage: MemoryFlagsStorage(), observeAppLifecycle: false),
          throwsArgumentError);
    });
  });

  group('cache and ETag', () {
    test('cache is served at start; If-None-Match only for the same request; 304 keeps results', () async {
      final storage = MemoryFlagsStorage();
      var answer304 = false;
      final server = FakeServer((req, _) => answer304
          ? http.Response('', 304, headers: {'etag': '"e2-abc"'})
          : ok({'theme': flag('theme', 'string', 'dark', variant: 'dark', reason: 'VARIANT')}));
      final a = await make(server, storage: storage);
      expect(server.requests.single.headers.containsKey('if-none-match'), isFalse);
      a.close();

      answer304 = true;
      final b = await make(server, storage: storage);
      expect(server.requests[1].headers['if-none-match'], '"e2-abc"');
      expect(b.getString('theme', 'light'), 'dark');
      expect(b.isReady, isTrue);

      // Different context → no If-None-Match.
      answer304 = false;
      await b.setAttributes({'plan': 'pro'});
      expect(server.requests[2].headers.containsKey('if-none-match'), isFalse);
      b.close();
    });

    test('offline: keeps serving the cache, never clears it', () async {
      final storage = MemoryFlagsStorage();
      var offline = false;
      final client = MockClient((req) async {
        if (offline) throw const SocketException('offline');
        return ok({'a': flag('a', 'boolean', true)});
      });
      final a = await RiviumFlags.create(const RiviumFlagsConfig(apiKey: _key),
          storage: storage, httpClient: client, observeAppLifecycle: false);
      a.close();
      offline = true;
      final b = await RiviumFlags.create(const RiviumFlagsConfig(apiKey: _key),
          storage: storage, httpClient: client, observeAppLifecycle: false);
      expect(b.getBool('a', false), isTrue);
      expect(b.lastError?.statusCode, isNull);
      expect(b.lastRetryDelay, isNotNull);
      expect(storage.values.containsKey('rivium_flags_cache_v2'), isTrue);
      b.close();
    });

    test('a changed userId drops the previous user results', () async {
      final storage = MemoryFlagsStorage();
      final server = FakeServer((req, body) {
        final uid = (body['context'] as Map)['userId'];
        return ok({'a': flag('a', 'string', 'for-$uid')});
      });
      final c = await make(server,
          storage: storage, config: const RiviumFlagsConfig(apiKey: _key, userId: 'u1'));
      expect(c.getString('a', ''), 'for-u1');
      final f = c.identify('u2');
      expect(c.isReady, isFalse); // dropped right away
      await f;
      expect(c.getString('a', ''), 'for-u2');
      c.close();

      // A cache of another user is not served at start.
      final d = await RiviumFlags.create(
          const RiviumFlagsConfig(apiKey: _key, userId: 'u3', initTimeout: Duration.zero),
          storage: storage,
          httpClient: MockClient((_) => Completer<http.Response>().future),
          observeAppLifecycle: false);
      expect(d.isReady, isFalse);
      d.close();
    });

    test('identify / setAttributes are debounced into one request', () async {
      final server = FakeServer((_, __) => ok({}));
      final c = await make(server);
      final f1 = c.setUserId('u1');
      final f2 = c.setAttributes({'plan': 'pro'});
      final f3 = c.identify('u1', attributes: {'plan': 'business', 'age': 31});
      await Future.wait([f1, f2, f3]);
      expect(server.requests, hasLength(2));
      expect(server.body(1)['context'],
          {'userId': 'u1', 'anonymousId': c.anonymousId, 'attributes': {'plan': 'business', 'age': 31}});
      c.close();
    });

    test('a newer context supersedes an older in-flight request', () async {
      final gates = <Completer<void>>[];
      final client = MockClient((req) async {
        final g = Completer<void>();
        gates.add(g);
        await g.future;
        final uid = ((jsonDecode(req.body) as Map)['context'] as Map)['userId'];
        return ok({'a': flag('a', 'string', 'for-$uid')});
      });
      final c = await RiviumFlags.create(
          const RiviumFlagsConfig(apiKey: _key, userId: 'old', initTimeout: Duration.zero),
          storage: MemoryFlagsStorage(),
          httpClient: client,
          observeAppLifecycle: false);
      final f = c.identify('new');
      await Future.delayed(const Duration(milliseconds: 300));
      expect(gates, hasLength(2));
      gates[1].complete();
      await f;
      gates[0].complete(); // the old answer arrives last
      await Future.delayed(const Duration(milliseconds: 20));
      expect(c.getString('a', ''), 'for-new');
      c.close();
    });
  });

  group('errors', () {
    Future<RiviumFlags> withStatus(int status,
        {Map<String, String> headers = const {}, String body = '{}'}) {
      return make(FakeServer((_, __) => http.Response(body, status, headers: headers)));
    }

    test('401 halts automatic fetches until refresh()', () async {
      final c = await withStatus(401,
          body: '{"statusCode":401,"error":"Unauthorized","message":"Invalid API key"}');
      expect(c.isHalted, isTrue);
      expect(c.lastError?.statusCode, 401);
      expect(c.lastError.toString().contains(_key), isFalse);
      expect(c.lastRetryDelay, isNull);
      c.close();
    });

    test('403 and 404 are not retried automatically', () async {
      for (final s in [403, 404]) {
        final c = await withStatus(s,
            body: '{"statusCode":$s,"code":"environment_not_found","message":"x"}');
        expect(c.isHalted, isTrue);
        expect(c.lastError?.code, 'environment_not_found');
        expect(c.lastRetryDelay, isNull);
        c.close();
      }
    });

    test('429 waits Retry-After, then backs off exponentially (±20 %, max 5 min)', () async {
      final c = await withStatus(429, headers: {'retry-after': '7'});
      expect(c.lastError?.statusCode, 429);
      expect(c.lastRetryDelay!.inMilliseconds, inInclusiveRange(7000, 8400));
      c.close();

      final d = await withStatus(429);
      expect(d.lastRetryDelay!.inMilliseconds, inInclusiveRange(5000, 6000));
      d.close();
    });

    test('5xx retries with back-off', () async {
      final c = await withStatus(503);
      expect(c.lastRetryDelay!.inMilliseconds, inInclusiveRange(4000, 6000));
      c.close();
    });

    test('400 is not re-sent with the same body', () async {
      final server = FakeServer((_, __) =>
          http.Response('{"statusCode":400,"code":"invalid_request","message":"bad"}', 400));
      final c = await make(server);
      await c.refresh(); // refresh clears the guard
      expect(server.requests, hasLength(2));
      c.close();
    });
  });

  group('polling and foreground', () {
    test('polling is off by default', () async {
      final server = FakeServer((_, __) => ok({}));
      final c = await make(server);
      expect(c.config.refreshIntervalSeconds, 0);
      c.close();
    });

    test('resume fetches only when the last success is older than 15 min', () async {
      final server = FakeServer((_, __) => ok({}));
      final c = await make(server);
      c.onBackground();
      c.onForeground();
      await Future.delayed(const Duration(milliseconds: 10));
      expect(server.requests, hasLength(1));
      c.close();
    });
  });
}
