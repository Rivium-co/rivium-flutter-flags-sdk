/// RiviumFeatureFlags SDK errors
class RiviumFeatureFlagsError implements Exception {
  final String code;
  final String message;

  const RiviumFeatureFlagsError(this.code, this.message);

  factory RiviumFeatureFlagsError.notInitialized() {
    return const RiviumFeatureFlagsError(
        'NOT_INITIALIZED', 'RiviumFeatureFlags SDK not initialized');
  }

  factory RiviumFeatureFlagsError.invalidConfig(String message) {
    return RiviumFeatureFlagsError(
        'INVALID_CONFIG', 'Invalid configuration: $message');
  }

  factory RiviumFeatureFlagsError.networkError(String message) {
    return RiviumFeatureFlagsError('NETWORK_ERROR', 'Network error: $message');
  }

  factory RiviumFeatureFlagsError.apiError(int code, String message) {
    return RiviumFeatureFlagsError(
        'API_ERROR', 'API error ($code): $message');
  }

  @override
  String toString() => 'RiviumFeatureFlagsError[$code]: $message';
}
