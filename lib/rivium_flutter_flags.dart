/// RiviumFeatureFlags - Standalone Feature Flags SDK for Flutter
///
/// Pure Dart implementation. Works on all Flutter platforms
/// (iOS, Android, Web, macOS, Windows, Linux).
///
/// Features:
/// - Feature flag evaluation with server-side and local fallback
/// - Offline support with local caching
/// - Rollout percentage targeting
/// - User attribute targeting rules
/// - Multivariate flags with weighted variants
///
/// Usage:
/// ```dart
/// import 'package:rivium_flutter_flags/rivium_flutter_flags.dart';
///
/// // Initialize
/// final flags = await RiviumFeatureFlags.init(
///   RiviumFeatureFlagsConfig(apiKey: 'rv_live_xxx'),
/// );
///
/// // Set user ID
/// await flags.setUserId('user-123');
///
/// // Check if feature is enabled
/// if (await flags.isEnabled('dark-mode')) {
///   // Show dark mode
/// }
///
/// // Get flag value
/// final value = await flags.getValue('banner-text', defaultValue: 'Welcome');
/// ```
library rivium_flutter_flags;

// Core SDK
export 'src/rivium_feature_flags.dart';
export 'src/rivium_feature_flags_config.dart';
export 'src/rivium_feature_flags_error.dart';

// Models
export 'src/models/feature_flag.dart';

// Storage (public types only)
export 'src/storage/flag_storage.dart' show CachedFeatureFlag, CachedFlagVariant;
