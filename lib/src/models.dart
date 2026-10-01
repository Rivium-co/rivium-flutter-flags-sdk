/// Why a flag has the value it has.
abstract final class RiviumFlagReason {
  /// Flag on, no variants: value `true`.
  static const on = 'ON';

  /// Flag on, a variant was served.
  static const variant = 'VARIANT';

  /// Flag is off in this environment.
  static const disabled = 'DISABLED';

  /// A prerequisite flag did not give the required result.
  static const prerequisiteFailed = 'PREREQUISITE_FAILED';

  /// Targeting rules did not match the context.
  static const notTargeted = 'NOT_TARGETED';

  /// Outside the rollout percentage.
  static const outsideRollout = 'OUTSIDE_ROLLOUT';

  /// A rollout or split needed an id and the context had none.
  static const noBucketingId = 'NO_BUCKETING_ID';

  /// Malformed flag configuration on the server; the off value was served.
  static const error = 'ERROR';

  /// The key is not in the results; the code default is returned.
  static const flagNotFound = 'FLAG_NOT_FOUND';

  /// No cached or fetched results yet; the code default is returned.
  static const notReady = 'NOT_READY';

  /// A typed getter was called on a flag of another value type; the code
  /// default is returned.
  static const typeMismatch = 'TYPE_MISMATCH';
}

/// One flag result as returned by `POST /public/v2/evaluate`.
class RiviumFlagResult {
  final String key;

  /// `boolean`, `string`, `number` or `json`.
  final String valueType;
  final bool enabled;
  final Object? value;
  final String? variant;
  final String reason;
  final int? version;

  const RiviumFlagResult({
    required this.key,
    required this.valueType,
    required this.enabled,
    required this.value,
    required this.variant,
    required this.reason,
    this.version,
  });

  factory RiviumFlagResult.fromJson(String key, Map<String, dynamic> json) {
    final version = json['version'];
    return RiviumFlagResult(
      key: (json['key'] as String?) ?? key,
      valueType: (json['valueType'] as String?) ?? 'json',
      enabled: json['enabled'] == true,
      value: json['value'],
      variant: json['variant'] as String?,
      reason: (json['reason'] as String?) ?? RiviumFlagReason.error,
      version: version is num ? version.toInt() : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'valueType': valueType,
        'enabled': enabled,
        'value': value,
        'variant': variant,
        'reason': reason,
        'version': version,
      };

  @override
  String toString() =>
      'RiviumFlagResult($key, enabled: $enabled, value: $value, variant: $variant, reason: $reason)';
}

/// What a getter returned and why.
class RiviumFlagDetail<T> {
  final T value;
  final bool enabled;
  final String? variant;
  final String reason;
  final int? version;

  const RiviumFlagDetail({
    required this.value,
    required this.enabled,
    required this.variant,
    required this.reason,
    this.version,
  });

  @override
  String toString() =>
      'RiviumFlagDetail(value: $value, enabled: $enabled, variant: $variant, reason: $reason, version: $version)';
}

/// The last request failure, for display or logs. Never contains the API key.
class RiviumFlagsError {
  /// HTTP status, or `null` for a network error.
  final int? statusCode;

  /// The server's `code` (e.g. `environment_not_found`) when present.
  final String? code;
  final String message;

  const RiviumFlagsError({this.statusCode, this.code, required this.message});

  @override
  String toString() =>
      'RiviumFlagsError(${statusCode ?? 'network'}${code != null ? ' $code' : ''}): $message';
}
