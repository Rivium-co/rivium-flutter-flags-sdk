import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:rivium_flutter_flags/rivium_flutter_flags.dart';

// Public key from Rivium Console → Flags → Settings (rv_live_… / rv_test_…).
const _apiKey = 'YOUR_API_KEY_HERE';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RiviumFlags.init(
    const RiviumFlagsConfig(apiKey: _apiKey, environment: 'production', debug: true),
  );
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rivium Flags',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const FlagsPage(),
    );
  }
}

class FlagsPage extends StatefulWidget {
  const FlagsPage({super.key});

  @override
  State<FlagsPage> createState() => _FlagsPageState();
}

class _FlagsPageState extends State<FlagsPage> {
  RiviumFlags get _flags => RiviumFlags.instance;
  late final StreamSubscription<void> _sub;
  final _userId = TextEditingController(text: 'user-1');
  final _plan = TextEditingController(text: 'pro');
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Re-render whenever new results arrive.
    _sub = _flags.onChange.listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _sub.cancel();
    _userId.dispose();
    _plan.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final all = _flags.getAll().values.toList()..sort((a, b) => a.key.compareTo(b.key));
    final error = _flags.lastError;
    return Scaffold(
      appBar: AppBar(title: const Text('Rivium Flags')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Anonymous id: ${_flags.anonymousId}', style: Theme.of(context).textTheme.bodySmall),
          Text('User: ${_flags.userId ?? '(signed out)'}  ·  ready: ${_flags.isReady}'),
          if (error != null)
            Text('Last error: $error', style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          TextField(controller: _userId, decoration: const InputDecoration(labelText: 'User id')),
          TextField(controller: _plan, decoration: const InputDecoration(labelText: 'Attribute "plan"')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => _flags.identify(_userId.text,
                      attributes: {'plan': _plan.text})),
              child: const Text('Identify'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(_flags.refresh),
              child: const Text('Refresh'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(_flags.reset),
              child: const Text('Sign out (reset)'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(_flags.resetAnonymousId),
              child: const Text('New anonymous id'),
            ),
          ]),
          const Divider(height: 32),
          Text('Typed getters', style: Theme.of(context).textTheme.titleMedium),
          _row('isEnabled("new-checkout", false)', '${_flags.isEnabled('new-checkout')}'),
          _row('getString("theme", "light")', _flags.getString('theme', 'light')),
          _row('getNumber("max-items", 10)', '${_flags.getNumber('max-items', 10)}'),
          _row('getDetail("missing-flag")', _flags.getDetail('missing-flag', 'default').reason),
          const Divider(height: 32),
          Text('All results (${all.length})', style: Theme.of(context).textTheme.titleMedium),
          for (final f in all)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(f.enabled ? Icons.toggle_on : Icons.toggle_off,
                  color: f.enabled ? Colors.green : Colors.grey),
              title: Text(f.key),
              subtitle: Text('${f.valueType} · ${jsonEncode(f.value)}'
                  '${f.variant != null ? ' · variant ${f.variant}' : ''} · ${f.reason}'),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontFamily: 'monospace'))),
          Text(value),
        ]),
      );
}
