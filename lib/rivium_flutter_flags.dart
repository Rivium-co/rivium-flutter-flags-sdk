/// Rivium Flags — feature flags for Flutter (client SDK).
///
/// Flags are evaluated on the Rivium server with your public key; the app
/// stores only the results (no targeting rules on the device).
///
/// ```dart
/// import 'package:rivium_flutter_flags/rivium_flutter_flags.dart';
///
/// final flags = await RiviumFlags.init(
///   const RiviumFlagsConfig(apiKey: 'rv_live_xxx', environment: 'production'),
/// );
/// await flags.identify('user-123', attributes: {'plan': 'pro'});
///
/// if (flags.isEnabled('new-checkout')) { /* … */ }
/// final theme = flags.getString('theme', 'light');
/// ```
library rivium_flutter_flags;

export 'src/config.dart';
export 'src/models.dart';
export 'src/rivium_flags.dart';
export 'src/storage.dart'
    show RiviumFlagsStorage, SharedPreferencesFlagsStorage, MemoryFlagsStorage;
