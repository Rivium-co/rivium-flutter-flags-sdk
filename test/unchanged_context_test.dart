import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rivium_flutter_flags/rivium_flutter_flags.dart';

const _key = 'rv_test_key';

http.Response _ok([String value = 'v']) => http.Response(
    jsonEncode({
      'environment': null,
      'evaluatedAt': '2026-10-01T12:00:00.000Z',
      'flags': {
        'a': {
          'key': 'a',
          'valueType': 'string',
          'enabled': true,
          'value': value,
          'variant': null,
          'reason': 'ON',
          'version': 1,
        }
      },
    }),
    200,
    headers: {'etag': '"e-$value"', 'content-type': 'application/json'});

/// Counts evaluate requests. With [gated] every request waits for [release].
class Server {
  final List<Map<String, dynamic>> bodies = [];
  final List<Completer<void>> gates = [];
  bool gated;
  int? failWith;

  Server({this.gated = false});

  int get count => bodies.length;

  Map<String, dynamic> context(int i) =>
      bodies[i]['context'] as Map<String, dynamic>;

  MockClient get client => MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        bodies.add(body);
        if (gated) {
          final g = Completer<void>();
          gates.add(g);
          await g.future;
        }
        final status = failWith;
        if (status != null) return http.Response('{}', status);
        return _ok('for-${(body['context'] as Map)['userId']}');
      });

  void release(int i) => gates[i].complete();
}

Future<RiviumFlags> _make(Server server, {RiviumFlagsConfig? config}) =>
    RiviumFlags.create(config ?? const RiviumFlagsConfig(apiKey: _key),
        storage: MemoryFlagsStorage(),
        httpClient: server.client,
        observeAppLifecycle: false);

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 400));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('unchanged context sends no request', () {
    test('identify with the same user and attributes: one request in total', () async {
      final server = Server();
      final c = await _make(server);
      await c.identify('u1', attributes: {'plan': 'pro'});
      expect(server.count, 2); // start + the new user

      var changes = 0;
      final sub = c.onChange.listen((_) => changes++);
      for (var i = 0; i < 5; i++) {
        await c.identify('u1', attributes: {'plan': 'pro'});
      }
      await c.identify('u1'); // attributes kept
      await c.setUserId('u1');
      await c.setAttributes({'plan': 'pro'});
      await _settle();

      expect(server.count, 2);
      expect(changes, 0);
      expect(c.getString('a', ''), 'for-u1'); // callers still read current values
      expect(c.userId, 'u1');
      await sub.cancel();
      c.close();
    });

    test('the same context as the one given in the config sends nothing', () async {
      final server = Server();
      final c = await _make(server,
          config: const RiviumFlagsConfig(
              apiKey: _key, userId: 'u1', attributes: {'plan': 'pro'}));
      await c.identify('u1', attributes: {'plan': 'pro'});
      await _settle();
      expect(server.count, 1);
      c.close();
    });

    test('null and an empty user id are both "signed out"', () async {
      final server = Server();
      final c = await _make(server);
      await c.identify(null);
      await c.setUserId('');
      await c.identify('', attributes: {});
      await _settle();
      expect(server.count, 1);
      c.close();
    });

    test('a changed user id sends a new request', () async {
      final server = Server();
      final c = await _make(server);
      await c.identify('u1');
      await c.identify('u1');
      await c.identify('u2');
      expect(server.count, 3);
      expect(server.context(2)['userId'], 'u2');
      expect(c.getString('a', ''), 'for-u2');
      c.close();
    });

    test('attributes: same content in another key order or as a new object is unchanged', () async {
      final server = Server();
      final c = await _make(server);
      await c.setAttributes({
        'plan': 'pro',
        'age': 31,
        'tags': ['a', 'b'],
        'beta': null,
      });
      expect(server.count, 2);

      await c.setAttributes({
        'beta': null,
        'tags': ['a', 'b'],
        'age': 31,
        'plan': 'pro',
      });
      await c.identify(null, attributes: {
        'age': 31,
        'beta': null,
        'plan': 'pro',
        'tags': List.of(['a', 'b']),
      });
      await _settle();
      expect(server.count, 2);
      c.close();
    });

    test('attributes: a real difference sends a new request', () async {
      final server = Server();
      final c = await _make(server);
      await c.setAttributes({
        'plan': 'pro',
        'tags': ['a', 'b'],
        'beta': null,
      });
      expect(server.count, 2);

      await c.setAttributes({
        'plan': 'pro',
        'tags': ['b', 'a'], // order inside a list matters
        'beta': null,
      });
      expect(server.count, 3);

      await c.setAttributes({
        'plan': 'pro',
        'tags': ['b', 'a'],
      }); // null is not the same as absent
      expect(server.count, 4);

      await c.setAttributes({
        'plan': 'business',
        'tags': ['b', 'a'],
      });
      expect(server.count, 5);

      await c.setAttributes({});
      expect(server.count, 6);
      await c.setAttributes({});
      await _settle();
      expect(server.count, 6);
      c.close();
    });

    test('a nested value changed in place is noticed', () async {
      final server = Server();
      final c = await _make(server);
      final tags = ['a'];
      final attributes = <String, Object?>{'tags': tags};
      await c.setAttributes(attributes);
      expect(server.count, 2);
      tags.add('b');
      await c.setAttributes(attributes);
      expect(server.count, 3);
      expect(server.context(2)['attributes'], {
        'tags': ['a', 'b']
      });
      c.close();
    });

    test('the same user after reset() sends a request', () async {
      final server = Server();
      final c = await _make(server);
      await c.identify('u1', attributes: {'plan': 'pro'});
      expect(server.count, 2);
      await c.reset();
      expect(server.count, 3);
      expect(server.context(2).containsKey('userId'), isFalse);
      await c.identify('u1', attributes: {'plan': 'pro'});
      expect(server.count, 4);
      expect(server.context(3)['userId'], 'u1');
      expect(c.getString('a', ''), 'for-u1');
      c.close();
    });

    test('refresh() always sends a request', () async {
      final server = Server();
      final c = await _make(server);
      await c.identify('u1');
      await c.identify('u1');
      expect(server.count, 2);
      await c.refresh();
      await c.refresh();
      expect(server.count, 4);
      c.close();
    });

    test('resume and polling are not affected', () async {
      final server = Server();
      final c = await _make(server);
      await c.identify(null);
      c.onBackground();
      c.onForeground(); // fresh results: nothing to fetch
      await _settle();
      expect(server.count, 1);
      c.close();
    });
  });

  group('unchanged context while a request is pending', () {
    test('before the first answer: joins the request in flight', () async {
      final server = Server(gated: true);
      final c = await _make(server,
          config: const RiviumFlagsConfig(
              apiKey: _key, userId: 'u1', initTimeout: Duration.zero));
      expect(server.count, 1);
      expect(c.isReady, isFalse);

      var done = 0;
      final calls = [
        c.identify('u1').then((_) => done++),
        c.setUserId('u1').then((_) => done++),
        c.identify('u1', attributes: {}).then((_) => done++),
      ];
      await _settle();
      expect(server.count, 1);
      expect(done, 0); // still waiting for the one request

      server.release(0);
      await Future.wait(calls);
      expect(done, 3);
      expect(server.count, 1);
      expect(c.getString('a', ''), 'for-u1');
      c.close();
    });

    test('while the request of a changed context is in flight: joins it', () async {
      final server = Server();
      final c = await _make(server);
      server.gated = true;
      final first = c.identify('u1', attributes: {'plan': 'pro'});
      await _settle(); // debounce passed, request 2 is in flight
      expect(server.count, 2);

      var joined = false;
      final again =
          c.identify('u1', attributes: {'plan': 'pro'}).then((_) => joined = true);
      await _settle();
      expect(server.count, 2);
      expect(joined, isFalse);

      server.release(0);
      await Future.wait([first, again]);
      expect(server.count, 2);
      expect(c.getString('a', ''), 'for-u1');
      c.close();
    });

    test('inside the debounce window: one request, every call completes', () async {
      final server = Server();
      final c = await _make(server);
      final calls = [
        c.identify('u1', attributes: {'plan': 'pro'}),
        c.identify('u1', attributes: {'plan': 'pro'}),
        c.setUserId('u1'),
        c.setAttributes({'plan': 'pro'}),
      ];
      await Future.wait(calls).timeout(const Duration(seconds: 2));
      expect(server.count, 2);
      expect(c.getString('a', ''), 'for-u1');
      c.close();
    });

    test('changed and changed back before the request: nothing is sent', () async {
      final server = Server();
      final c = await _make(server);
      await c.setAttributes({'plan': 'pro'});
      expect(server.count, 2);
      final a = c.setAttributes({'plan': 'business'});
      final b = c.setAttributes({'plan': 'pro'});
      await Future.wait([a, b]).timeout(const Duration(seconds: 2));
      await _settle();
      expect(server.count, 2);
      c.close();
    });
  });

  group('unchanged context without results', () {
    test('after a failed request the call still tries again', () async {
      final server = Server()..failWith = 503;
      final c = await _make(server);
      expect(server.count, 1);
      expect(c.isReady, isFalse);
      server.failWith = null;
      await c.identify(null);
      expect(server.count, 2);
      expect(c.isReady, isTrue);
      c.close();
    });
  });
}
