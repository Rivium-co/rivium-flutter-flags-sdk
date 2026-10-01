/// Configuration for [RiviumFlags].
class RiviumFlagsConfig {
  /// Public project key (`rv_live_…` or `rv_test_…`). Never put a server
  /// secret in an app.
  final String apiKey;

  /// Environment key (`production`, `staging`, `development` or a custom
  /// one). `null` evaluates the Default layer.
  final String? environment;

  /// Only evaluate these flags. `null` evaluates every flag of the project.
  final List<String>? flagKeys;

  /// Initial signed-in user id. Use [RiviumFlags.identify] later on.
  final String? userId;

  /// Initial targeting attributes: string, number, bool, null or a list of
  /// those. No nested maps.
  final Map<String, Object?> attributes;

  /// Optional polling while the app is in the foreground, in seconds.
  /// `0` (default) = off; otherwise at least 60. Every evaluate request is a
  /// billed usage event, which is why polling is off by default.
  final int refreshIntervalSeconds;

  /// How long [RiviumFlags.init] waits for the first network answer before
  /// returning (the fetch keeps going in the background).
  final Duration initTimeout;

  /// Verbose logging. Errors are always logged.
  final bool debug;

  /// API base URL. Leave the default unless Rivium support tells you otherwise.
  final String baseUrl;

  const RiviumFlagsConfig({
    required this.apiKey,
    this.environment,
    this.flagKeys,
    this.userId,
    this.attributes = const {},
    this.refreshIntervalSeconds = 0,
    this.initTimeout = const Duration(seconds: 5),
    this.debug = false,
    this.baseUrl = 'https://flags.rivium.co',
  });
}
