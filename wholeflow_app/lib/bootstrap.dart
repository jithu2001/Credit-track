import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/api/api_client.dart';
import 'core/app_info.dart';
import 'core/connection/business_connection.dart';
import 'core/connection/connect_screen.dart';
import 'core/errors/error_reporter.dart';
import 'core/providers.dart';
import 'core/upgrade/upgrade_gate.dart';

/// Starts the app: with the business saved on the connect screen, or the
/// connect screen itself.
///
/// [flavor] is `owner` or `staff` (sent with error reports and used for the
/// store link on the "Update required" screen).
Future<void> bootstrapWholeFlow({required Widget appWidget, required String title, required String flavor}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final info = await AppInfo.load(flavor: flavor);
  _hookErrorReports();
  final prefs = await SharedPreferences.getInstance();
  final store = ConnectionStore(prefs);
  var clientReady = false;

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
    ErrorReporter.instance = null;
    await Supabase.instance.dispose();
    clientReady = false;
    showConnect();
  }

  start = (c) async {
    if (clientReady) await Supabase.instance.dispose();
    await Supabase.initialize(
      url: c.baseUrl,
      publishableKey: c.anonKey,
      // Every login request carries the app version; a 426 answer (too old)
      // opens the "Update required" screen, also for automatic token refreshes.
      headers: info.headers,
      httpClient: AppHttpClient(info.headers),
      authOptions: FlutterAuthClientOptions(localStorage: SharedPreferencesLocalStorage(persistSessionKey: c.sessionKey)),
    );
    clientReady = true;
    final auth = Supabase.instance.client.auth;
    final reportsApi = ApiClient(
      baseUrl: c.baseUrl,
      headers: info.headers,
      // The current token only: a report never refreshes or creates a session.
      token: () async {
        final s = auth.currentSession;
        return s == null || s.isExpired ? null : s.accessToken;
      },
    );
    ErrorReporter.instance = ErrorReporter(
      post: (body) => reportsApi.post('client-errors', body),
      signedIn: () => auth.currentSession?.isExpired == false,
      appVersion: info.version,
      platform: info.platform,
      flavor: info.flavor,
    );
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

  final saved = store.load();
  if (saved == null) {
    showConnect();
  } else {
    await start(saved);
  }
}

/// Uncaught errors (Flutter framework and everything else) go to the
/// connected business's server as error reports (core/errors/error_reporter.dart),
/// besides being printed as before.
void _hookErrorReports() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    (previous ?? FlutterError.presentError)(details);
    if (!details.silent) ErrorReporter.reportError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error');
    ErrorReporter.reportError(error, stack);
    return true;
  };
}
