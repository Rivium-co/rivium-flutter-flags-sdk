import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cached feature flag
class CachedFeatureFlag {
  final String key;
  final bool enabled;
  final int rolloutPercentage;
  final Map<String, dynamic>? targetingRules;
  final List<CachedFlagVariant>? variants;
  final dynamic defaultValue;
  final DateTime cachedAt;

  CachedFeatureFlag({
    required this.key,
    required this.enabled,
    this.rolloutPercentage = 100,
    this.targetingRules,
    this.variants,
    this.defaultValue,
    required this.cachedAt,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'enabled': enabled,
        'rolloutPercentage': rolloutPercentage,
        'targetingRules': targetingRules,
        'variants': variants?.map((v) => v.toJson()).toList(),
        'defaultValue': defaultValue,
        'cachedAt': cachedAt.toIso8601String(),
      };

  factory CachedFeatureFlag.fromJson(Map<String, dynamic> json) =>
      CachedFeatureFlag(
        key: json['key'] as String,
        enabled: json['enabled'] as bool? ?? false,
        rolloutPercentage: json['rolloutPercentage'] as int? ?? 100,
        targetingRules: json['targetingRules'] != null
            ? Map<String, dynamic>.from(json['targetingRules'] as Map)
            : null,
        variants: (json['variants'] as List?)
            ?.map(
                (v) => CachedFlagVariant.fromJson(Map<String, dynamic>.from(v)))
            .toList(),
        defaultValue: json['defaultValue'],
        cachedAt: json['cachedAt'] != null
            ? DateTime.parse(json['cachedAt'] as String)
            : DateTime.now(),
      );
}

/// Cached flag variant
class CachedFlagVariant {
  final String key;
  final dynamic value;
  final int weight;

  CachedFlagVariant({
    required this.key,
    this.value,
    this.weight = 0,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
        'weight': weight,
      };

  factory CachedFlagVariant.fromJson(Map<String, dynamic> json) =>
      CachedFlagVariant(
        key: json['key'] as String,
        value: json['value'],
        weight: json['weight'] as int? ?? 0,
      );
}

/// Lightweight offline storage for feature flags only
class FlagStorage {
  static const String _flagsKey = 'rivium_ff_cached_flags';
  static const String _userIdKey = 'rivium_ff_user_id';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ============================================
  // FLAG CACHE
  // ============================================

  Future<List<CachedFeatureFlag>> getCachedFlags() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_flagsKey);
    if (jsonStr == null) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList
          .map(
              (e) => CachedFeatureFlag.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> cacheFlags(List<CachedFeatureFlag> flags) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(flags.map((f) => f.toJson()).toList());
    await prefs.setString(_flagsKey, jsonStr);
  }

  Future<void> clearFlagCache() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.remove(_flagsKey);
  }

  // ============================================
  // USER ID
  // ============================================

  Future<String?> getUserId() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  Future<void> saveUserId(String userId) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
  }

  // ============================================
  // CLEAR ALL
  // ============================================

  Future<void> clearAll() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.remove(_flagsKey);
    await prefs.remove(_userIdKey);
  }
}
