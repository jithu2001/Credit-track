import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Env.isConfigured) {
    runApp(const _NotConfiguredApp());
    return;
  }
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        supabaseProvider.overrideWithValue(Supabase.instance.client),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      // Screens offer an explicit Retry; don't retry failed loads silently.
      retry: (retryCount, error) => null,
      child: const WholeFlowApp(),
    ),
  );
}

/// Shown when the build lacks SUPABASE_URL / SUPABASE_ANON_KEY.
class _NotConfiguredApp extends StatelessWidget {
  const _NotConfiguredApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(Insets.xl),
            child: Text(
              'This build is missing its Supabase settings.\n'
              'Run with --dart-define-from-file=env/dev.json (see README).',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
