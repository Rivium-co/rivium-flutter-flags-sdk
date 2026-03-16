import 'package:flutter/material.dart';
import 'package:rivium_flutter_flags/rivium_flutter_flags.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await RiviumFeatureFlags.init(
    RiviumFeatureFlagsConfig(
      apiKey: 'Your api key', // Replace with your API key
      debug: true,
    ),
    callback: (event, data) {
      debugPrint('RiviumFlags: $event → $data');
    },
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RiviumFlags Test',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
      ),
      home: const FlagTestPage(),
    );
  }
}

class FlagTestPage extends StatefulWidget {
  const FlagTestPage({super.key});

  @override
  State<FlagTestPage> createState() => _FlagTestPageState();
}

class _FlagTestPageState extends State<FlagTestPage> {
  RiviumFeatureFlags get _flags => RiviumFeatureFlags.instance;
  List<FeatureFlag> _allFlags = [];
  bool _loading = true;
  final List<_TestResult> _results = [];
  String _userId = 'test-user-1';
  String _selectedEnv = 'none';

  @override
  void initState() {
    super.initState();
    _runAllTests();
  }

  Future<void> _runAllTests() async {
    setState(() {
      _loading = true;
      _results.clear();
    });

    // ── Set user context ──
    await _flags.setUserId(_userId);
    _flags.setUserAttributes({'plan': 'pro', 'country': 'US'});

    // ── Test 1: Fetch all flags ──
    final allFlags = await _flags.getAll();
    _addResult(
      'GET /public/flags',
      'Fetched ${allFlags.length} flags: ${allFlags.map((f) => f.key).join(", ")}',
      allFlags.isNotEmpty,
    );
    setState(() => _allFlags = allFlags);

    // ── Test 2: Simple boolean flag (dark_mode) ──
    final darkMode = await _flags.isEnabled('dark_mode');
    _addResult(
      'Boolean flag: dark_mode',
      'isEnabled = $darkMode (expected: true)',
      true,
    );

    // ── Test 3: Multivariate flag (checkout_flow) ──
    final checkoutEnabled = await _flags.isEnabled('checkout_flow');
    final checkoutValue = await _flags.getValue('checkout_flow');
    _addResult(
      'Multivariate: checkout_flow',
      'enabled=$checkoutEnabled, value=$checkoutValue',
      true,
    );

    // ── Test 4: Targeting rules (premium_banner) ──
    // With plan=pro, country=US → should match
    final premiumMatch = await _flags.isEnabled('premium_banner');
    _addResult(
      'Targeting (plan=pro, country=US)',
      'premium_banner = $premiumMatch (expected: true)',
      true,
    );

    // Change to non-matching attributes
    _flags.setUserAttributes({'plan': 'free', 'country': 'IR'});
    final premiumNoMatch = await _flags.isEnabled('premium_banner');
    _addResult(
      'Targeting (plan=free, country=IR)',
      'premium_banner = $premiumNoMatch (expected: false)',
      true,
    );

    // Restore attributes
    _flags.setUserAttributes({'plan': 'pro', 'country': 'US'});

    // ── Test 5: Gradual rollout (gradual_redesign, 30%) ──
    // Test multiple user IDs to see rollout bucketing
    final rolloutResults = <String, bool>{};
    for (final uid in ['user-1', 'user-2', 'user-3', 'user-4', 'user-5']) {
      await _flags.setUserId(uid);
      final result = await _flags.isEnabled('gradual_redesign');
      rolloutResults[uid] = result;
    }
    final enabledCount = rolloutResults.values.where((v) => v).length;
    _addResult(
      'Rollout 30%: gradual_redesign',
      '${rolloutResults.entries.map((e) => "${e.key}=${e.value}").join(", ")}\n'
          '$enabledCount/5 users enabled (~30% expected)',
      true,
    );

    // Restore user
    await _flags.setUserId(_userId);
    _flags.setUserAttributes({'plan': 'pro', 'country': 'US'});

    // ── Test 6: Flag dependency (vip_checkout depends on dark_mode) ──
    final vipCheckout = await _flags.isEnabled('vip_checkout');
    _addResult(
      'Dependency: vip_checkout → dark_mode',
      'vip_checkout = $vipCheckout (depends on dark_mode being enabled)',
      true,
    );

    // ── Test 7: Non-existent flag (default value) ──
    final missing = await _flags.isEnabled(
      'nonexistent_flag',
      defaultValue: false,
    );
    final missingValue = await _flags.getValue(
      'nonexistent_flag',
      defaultValue: 'fallback',
    );
    _addResult(
      'Default value: nonexistent_flag',
      'isEnabled=$missing (default: false), getValue=$missingValue (default: "fallback")',
      true,
    );

    // ── Test 8: Evaluate (full result) ──
    final evalResult = await _flags.evaluate('checkout_flow');
    _addResult(
      'Evaluate: checkout_flow',
      'enabled=${evalResult.enabled}, value=${evalResult.value}, variant=${evalResult.variant}',
      true,
    );

    // ── Test 9: getUserId ──
    final currentUserId = _flags.getUserId();
    _addResult(
      'getUserId',
      'getUserId = "$currentUserId" (expected: "$_userId")',
      currentUserId == _userId,
    );

    // ── Test 10: Offline cache ──
    _addResult(
      'Offline cache',
      'Cached ${_flags.cachedFlags.length} flags locally. '
          'Online: ${_flags.isOnline}',
      true,
    );

    // ── Test 11: Refresh ──
    await _flags.refresh();
    _addResult(
      'Manual refresh',
      'Refreshed flags from server. Cache: ${_flags.cachedFlags.length} flags',
      true,
    );

    // ── Test 12: Environment overrides ──
    // Compare flag values across different environments.
    // Setup in dashboard:
    //   1. Create a flag (e.g. "maintenance_mode") → globally disabled
    //   2. Create environments: development, staging, production
    //   3. Override: development → enabled, staging → enabled, production → keep default
    // Then this test shows different values per environment.
    final envResults = <String, Map<String, dynamic>>{};
    final testFlagKey = _allFlags.isNotEmpty
        ? _allFlags.first.key
        : 'maintenance_mode';

    try {
      for (final env in ['none', 'development', 'staging', 'production']) {
        try {
          await RiviumFeatureFlags.instance.reset();
        } catch (_) {
          // Instance may already be null after previous reset
        }
        final envConfig = RiviumFeatureFlagsConfig(
          apiKey: 'YOUR_API_KEY',
          environment: env == 'none' ? null : env,
          debug: true,
          enableOfflineCache: false, // avoid cache interference between envs
        );
        final envFlags = await RiviumFeatureFlags.init(envConfig);
        await envFlags.setUserId(_userId);
        // Use cachedFlags (already fetched by init) to avoid extra HTTP call
        final flagEnabled = await envFlags.isEnabled(testFlagKey);
        final flagValue = await envFlags.getValue(testFlagKey);
        envResults[env] = {
          'totalFlags': envFlags.cachedFlags.length,
          'enabled': flagEnabled,
          'value': flagValue,
        };
      }
    } catch (e) {
      debugPrint('RiviumFlags: Environment test error: $e');
    }

    // Re-init with the selected environment for the rest of the session
    try {
      await RiviumFeatureFlags.instance.reset();
    } catch (_) {}
    final reinited = await RiviumFeatureFlags.init(
      RiviumFeatureFlagsConfig(
        apiKey: 'YOUR_API_KEY',
        environment: _selectedEnv == 'none' ? null : _selectedEnv,
        debug: true,
      ),
    );
    await reinited.setUserId(_userId);
    reinited.setUserAttributes({'plan': 'pro', 'country': 'US'});

    final envDetail = envResults.entries
        .map(
          (e) =>
              '${e.key}: enabled=${e.value['enabled']}, value=${e.value['value']}, flags=${e.value['totalFlags']}',
        )
        .join('\n');
    _addResult(
      'Environment overrides: $testFlagKey',
      'Flag "$testFlagKey" across environments:\n$envDetail',
      true,
    );

    // ── Test 13: Reset & Dispose ──
    final flagsBefore = _flags.cachedFlags.length;
    _flags.dispose();
    await _flags.reset();
    // Re-init for next run
    final reinited2 = await RiviumFeatureFlags.init(
      RiviumFeatureFlagsConfig(
        apiKey: 'YOUR_API_KEY',
        environment: _selectedEnv == 'none' ? null : _selectedEnv,
        debug: true,
      ),
    );
    _addResult(
      'Reset & Dispose',
      'Before: $flagsBefore flags, dispose() called, After reset+reinit: ${reinited2.cachedFlags.length} flags',
      true,
    );

    setState(() => _loading = false);
  }

  void _addResult(String test, String detail, bool pass) {
    _results.add(_TestResult(test: test, detail: detail, pass: pass));
  }

  Future<void> _switchUser(String newUserId) async {
    setState(() => _userId = newUserId);
    _runAllTests();
  }

  Future<void> _switchEnvironment(String env) async {
    setState(() => _selectedEnv = env);
    // Reset and re-init with the new environment
    await RiviumFeatureFlags.instance.reset();
    await RiviumFeatureFlags.init(
      RiviumFeatureFlagsConfig(
        apiKey: 'YOUR_API_KEY',
        environment: env == 'none' ? null : env,
        debug: true,
      ),
      callback: (event, data) {
        debugPrint('RiviumFlags: $event → $data');
      },
    );
    _runAllTests();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RiviumFlags Test Suite'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _runAllTests),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // User switcher
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: Colors.amber.shade50,
                  child: Row(
                    children: [
                      const Text(
                        'User: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children:
                                ['test-user-1', 'test-user-2', 'test-user-3']
                                    .map(
                                      (uid) => Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: ChoiceChip(
                                          label: Text(
                                            uid,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                          selected: _userId == uid,
                                          onSelected: (_) => _switchUser(uid),
                                        ),
                                      ),
                                    )
                                    .toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Environment switcher
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: Colors.blue.shade50,
                  child: Row(
                    children: [
                      const Text(
                        'Env: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children:
                                ['none', 'development', 'staging', 'production']
                                    .map(
                                      (env) => Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: ChoiceChip(
                                          label: Text(
                                            env == 'none' ? 'Global' : env,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                          selected: _selectedEnv == env,
                                          onSelected: (_) =>
                                              _switchEnvironment(env),
                                          selectedColor: Colors.blue.shade200,
                                        ),
                                      ),
                                    )
                                    .toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Connection status
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  color: _flags.isOnline
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  child: Row(
                    children: [
                      Icon(
                        _flags.isOnline ? Icons.wifi : Icons.wifi_off,
                        size: 16,
                        color: _flags.isOnline ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _flags.isOnline
                            ? 'Online — ${_allFlags.length} flags loaded'
                            : 'Offline — using ${_flags.cachedFlags.length} cached flags',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),

                // Test results
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final r = _results[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Test ${index + 1}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      r.test,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  r.detail,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _TestResult {
  final String test;
  final String detail;
  final bool pass;

  _TestResult({required this.test, required this.detail, required this.pass});
}
