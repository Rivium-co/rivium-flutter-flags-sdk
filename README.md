<p align="center">
  <a href="https://rivium.co">
    <img src="https://rivium.co/logo.png" alt="Rivium" width="120" />
  </a>
</p>

<h3 align="center">Rivium Flags Flutter SDK</h3>

<p align="center">
  Feature flag management for Flutter with offline caching, targeting rules, and rollout control.
</p>

<p align="center">
  <a href="https://pub.dev/packages/rivium_flutter_flags"><img src="https://img.shields.io/pub/v/rivium_flutter_flags.svg" alt="pub.dev" /></a>
  <img src="https://img.shields.io/badge/Dart-3.0+-0175C2?logo=dart&logoColor=white" alt="Dart 3.0+" />
  <img src="https://img.shields.io/badge/Flutter-all_platforms-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="MIT License" />
</p>

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  rivium_flutter_flags: ^0.1.0
```

Then run:

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:rivium_flutter_flags/rivium_flutter_flags.dart';

// Initialize
final flags = await RiviumFeatureFlags.init(
  RiviumFeatureFlagsConfig(
    apiKey: 'YOUR_API_KEY',
    environment: 'production',
    enableOfflineCache: true,
  ),
);

// Set user context
await flags.setUserId('user-123');
flags.setUserAttributes({'plan': 'pro', 'country': 'US'});

// Check flags
final darkMode = await flags.isEnabled('dark_mode');
final variant = await flags.getValue('checkout_flow');

// Full evaluation
final result = await flags.evaluate('checkout_flow');
print('enabled: ${result.enabled}, value: ${result.value}, variant: ${result.variant}');

// Refresh from server
await flags.refresh();
```

## Features

- **Boolean & Multivariate Flags** — Simple on/off toggles or multi-variant flags with weighted distribution
- **Targeting Rules** — Target users by attributes (equals, contains, regex, in, greater_than, and more)
- **Rollout Percentages** — Gradual rollouts with deterministic MD5-based bucketing
- **Offline Caching** — Flags cached with shared_preferences for offline access
- **Environment Overrides** — Separate flag values per environment (development, staging, production)
- **Pure Dart** — Works on all Flutter platforms (iOS, Android, Web, macOS, Windows, Linux)
- **Connectivity Aware** — Automatic online/offline detection

## Documentation

For full documentation, visit [rivium.co/docs](https://rivium.co/docs).

## License

MIT License — see [LICENSE](LICENSE) for details.
