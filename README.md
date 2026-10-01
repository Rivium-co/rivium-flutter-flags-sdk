<p align="center">
  <a href="https://rivium.co">
    <img src="https://rivium.co/logo.png" alt="Rivium" width="120" />
  </a>
</p>

<h3 align="center">Rivium Flags Flutter SDK</h3>

<p align="center">
  Feature flags for Flutter. Flags are evaluated on the Rivium server; the app keeps only the results.
</p>

<p align="center">
  <a href="https://pub.dev/packages/rivium_flutter_flags"><img src="https://img.shields.io/pub/v/rivium_flutter_flags.svg" alt="pub.dev" /></a>
  <img src="https://img.shields.io/badge/Dart-3.0+-0175C2?logo=dart&logoColor=white" alt="Dart 3.0+" />
  <img src="https://img.shields.io/badge/Flutter-all_platforms-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="MIT License" />
</p>

---

## Installation

```yaml
dependencies:
  rivium_flutter_flags: ^0.2.0
```

```bash
flutter pub get
```

Works on iOS, Android, web, macOS, Windows and Linux (Flutter 3.13+).

## Quick start

```dart
import 'package:rivium_flutter_flags/rivium_flutter_flags.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RiviumFlags.init(const RiviumFlagsConfig(
    apiKey: 'rv_live_xxx',          // public key: Console → Flags → Settings
    environment: 'production',     // omit for the Default layer
  ));
  runApp(const MyApp());
}

final flags = RiviumFlags.instance;

if (flags.isEnabled('new-checkout')) {
  // …
}
final theme = flags.getString('theme', 'light');
final maxItems = flags.getNumber('max-items', 10);
final layout = flags.getJson('home-layout', {'columns': 2});
```

`init` serves the results cached on the device right away and waits up to `initTimeout` (5 s) for the network.
Getters are synchronous and never throw: when a flag is unknown, results are not ready yet, or the type does
not match, they return the default you passed.

## Identify users

```dart
// After sign-in (debounced 250 ms; results of the previous user are dropped):
await flags.identify('user-123', attributes: {'plan': 'pro', 'country': 'AM', 'beta': true});

await flags.setAttributes({'plan': 'business'}); // replaces all attributes
await flags.setUserId(null);                     // signed out, same as identify(null)

// Sign-out: clears user id, attributes and cached results; keeps the anonymous id.
await flags.reset();
```

Every install gets a random anonymous id (UUID v4, stored with `shared_preferences` as
`rivium_flags_anonymous_id`). It is sent with every request, so percentage rollouts work for signed-out users
too. It survives `reset()`; `resetAnonymousId()` replaces it.

Attributes are strings, numbers, booleans, null, or lists of those (no nested maps, at most 100).

## Reasons and details

```dart
final d = flags.getStringDetail('theme', 'light');
print('${d.value} ${d.enabled} ${d.variant} ${d.reason} ${d.version}');
```

| Reason | Meaning |
|---|---|
| `ON` / `VARIANT` | flag on (no variants / a variant was served) |
| `DISABLED`, `NOT_TARGETED`, `OUTSIDE_ROLLOUT`, `PREREQUISITE_FAILED`, `NO_BUCKETING_ID`, `ERROR` | flag off for this user; the flag's off value is served |
| `FLAG_NOT_FOUND` | no such flag; your default is returned |
| `NOT_READY` | no cached or fetched results yet; your default is returned |
| `TYPE_MISMATCH` | e.g. `getString` on a boolean flag; your default is returned |

`isEnabled(key)` is `true` only for `ON` and `VARIANT`. `getDetail(key, default)` returns the stored value
without a type check; `getAll()` returns every result.

## Updates

```dart
flags.onChange.listen((_) => setState(() {}));   // new results arrived
flags.onError.listen((e) => print(e.statusCode)); // request failures
await flags.refresh();                            // fetch now
```

Results are fetched on `init`, on `identify` / `setUserId` / `setAttributes`, when the app returns to the
foreground and the last fetch is older than 15 minutes, and on `refresh()`. Optional polling while in the
foreground: `refreshIntervalSeconds: 300` (default 0 = off, minimum 60). **Each fetch is a billed evaluation
request**, which is why polling is off by default.

Offline or on errors the last good results keep being served. 429 and 5xx are retried with back-off
(`Retry-After`, then ×2 up to 5 minutes). 401 / 403 / 404 (bad key, Flags not enabled, unknown environment)
stop automatic fetches until `refresh()` or the next start.

Call `flags.close()` when you no longer need a client.

## Client vs server SDKs

This is a **client** SDK: it uses the public key and calls `POST /public/v2/evaluate`; targeting rules never
reach the device. Never put the server secret (`rv_srv_…`) in an app — `init` refuses it. For local evaluation on
a backend, use the Node.js or Next.js server SDK.

## Migrating from 0.1.x

0.2.0 is a new API (the 0.1.x route no longer serves client keys):

| 0.1.x | 0.2.0 |
|---|---|
| `RiviumFeatureFlags.init(RiviumFeatureFlagsConfig(...))` | `RiviumFlags.init(RiviumFlagsConfig(...))` |
| `RiviumFeatureFlags.instance` | `RiviumFlags.instance` |
| `await flags.isEnabled('k')` | `flags.isEnabled('k')` (synchronous) |
| `await flags.getValue('k', defaultValue: x)` | `getBool` / `getString` / `getNumber` / `getJson('k', x)` |
| `await flags.evaluate('k')` | `getDetail('k', default)` (adds `reason`, `version`) |
| `setUserAttributes(map)` (merged) | `setAttributes(map)` (replaces) or `identify(id, attributes: …)` |
| `getAll()` (flag configs) | `getAll()` (results only) |
| `callback: (event, data)` | `onChange` / `onError` streams |
| `enableOfflineCache`, `isOnline`, `cachedFlags`, `dispose()` | always cached; `lastError`; `close()` |

The entry point was renamed from `RiviumFeatureFlags` to `RiviumFlags` so it no longer clashes with
`RiviumFeatureFlags` in the Rivium A/B Testing Flutter SDK; both packages can be imported together. Users are
bucketed by a new hash in 0.2.0, so percentage rollouts reshuffle once.

## Testing

Pass `storage: MemoryFlagsStorage()` and your own `http.Client` (e.g. `MockClient` from `package:http/testing.dart`)
to `RiviumFlags.create(...)`, which does not touch `RiviumFlags.instance`.

## Documentation

- [Rivium Flags Flutter docs](https://rivium.co/cloud/rivium-flags/docs/sdks-flutter)
- [Rivium Cloud](https://rivium.co/cloud)
- [Rivium Console](https://console.rivium.co)

## License

MIT License — see [LICENSE](LICENSE) for details.
