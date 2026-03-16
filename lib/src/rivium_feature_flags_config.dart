/// Configuration for RiviumFeatureFlags SDK
class RiviumFeatureFlagsConfig {
  /// API key for authentication (format: rv_live_xxx or rv_test_xxx)
  final String apiKey;

  /// Environment key (e.g. 'production', 'staging', 'development')
  /// When set, the server returns flag values with environment-specific overrides.
  final String? environment;

  /// Enable debug logging
  final bool debug;

  /// Enable offline caching of flags
  final bool enableOfflineCache;

  /// Base URL for the API (internal, not configurable)
  static const String baseUrl = 'https://flags.rivium.co';

  const RiviumFeatureFlagsConfig({
    required this.apiKey,
    this.environment,
    this.debug = false,
    this.enableOfflineCache = true,
  });
}
