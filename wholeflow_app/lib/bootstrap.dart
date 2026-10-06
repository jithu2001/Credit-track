import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/connection/business_connection.dart';
import 'core/connection/connect_screen.dart';
import 'core/env.dart';
import 'core/providers.dart';

/// Starts the app: with the build's fixed project, or the business saved on
/// the connect screen, or the connect screen itself.
Future<void> bootstrapWholeFlow({required Widget appWidget, required String title}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final store = ConnectionStore(prefs);
  var supabaseReady = false;

  late Future<void> Function(BusinessConnection) start;

  void showConnect() => runApp(
    ConnectApp(
      title: title,
      onConnected: (c) async {
        await store.save(c);
        await start(c);
      },
    ),
  );

  Future<void> switchBusiness() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // Offline: the session is dropped with the connection below.
    }
    await store.clear();
    await Supabase.instance.dispose();
    supabaseReady = false;
    showConnect();
  }

  start = (c) async {
    if (supabaseReady) await Supabase.instance.dispose();
    final sessionKey = c.sessionKey;
    await Supabase.initialize(
      url: c.baseUrl,
      publishableKey: c.anonKey,
      authOptions: sessionKey == null
          ? const FlutterAuthClientOptions()
          : FlutterAuthClientOptions(localStorage: SharedPreferencesLocalStorage(persistSessionKey: sessionKey)),
    );
    supabaseReady = true;
    runApp(
      ProviderScope(
        overrides: [
          supabaseProvider.overrideWithValue(Supabase.instance.client),
          sharedPreferencesProvider.overrideWithValue(prefs),
          businessConnectionProvider.overrideWithValue(c),
          switchBusinessProvider.overrideWithValue(switchBusiness),
        ],
        // Screens offer an explicit Retry; don't retry failed loads silently.
        retry: (retryCount, error) => null,
        child: appWidget,
      ),
    );
  };

  final saved = Env.hasFixedProject ? BusinessConnection.fixed() : store.load();
  if (saved == null) {
    showConnect();
  } else {
    await start(saved);
  }
}
