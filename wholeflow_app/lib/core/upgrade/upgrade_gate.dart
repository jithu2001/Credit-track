import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Set once the server refuses a request because this app version is too old
/// (HTTP 426 `UPGRADE_REQUIRED` / `upgrade_required`). The app then shows only
/// the "Update required" screen (UpdateRequiredFrame) until it is updated.
///
/// A plain notifier rather than a provider: it is raised from the HTTP layer,
/// including the login client's own token refreshes.
abstract final class UpgradeGate {
  static final ValueNotifier<String?> _message = ValueNotifier(null);

  /// The server's text for the update screen; null while the app may run.
  static ValueListenable<String?> get message => _message;

  static bool get required => _message.value != null;

  static void trigger([String? serverMessage]) {
    final text = serverMessage?.trim();
    final next = text == null || text.isEmpty ? defaultMessage : text;
    if (_message.value == next) return;
    // Deferred: errors are also mapped while widgets build.
    scheduleMicrotask(() => _message.value = next);
  }

  static const defaultMessage = 'This version of WholeFlow is no longer supported. Update the app to continue.';

  @visibleForTesting
  static void reset() => _message.value = null;
}

/// The HTTP client the login library uses: adds the app version headers to
/// every request and raises [UpgradeGate] on HTTP 426, also for requests the
/// library makes by itself (token refresh).
class AppHttpClient extends http.BaseClient {
  AppHttpClient(this._headers, [http.Client? inner]) : _inner = inner ?? http.Client();

  final Map<String, String> _headers;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(_headers);
    final res = await _inner.send(request);
    if (res.statusCode == 426) UpgradeGate.trigger();
    return res;
  }

  @override
  void close() => _inner.close();
}
