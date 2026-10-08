import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Sends crashes and uncaught errors to the business's server
/// (`POST /api/v1/client-errors`), so problems in the field show up on the
/// server's health page.
///
/// Fire-and-forget and careful: only while signed in, at most [maxPerRun]
/// reports per app run, each distinct message once, and only the error text
/// and stack trace (with anything that looks like a token removed), never
/// screen data, passwords or tokens.
class ErrorReporter {
  ErrorReporter({
    required this.post,
    required this.signedIn,
    required this.appVersion,
    required this.platform,
    required this.flavor,
    this.maxPerRun = 5,
  });

  /// Sends one report body; set up by bootstrap with the app API client.
  final Future<void> Function(Map<String, String> body) post;
  final bool Function() signedIn;
  final String appVersion;
  final String platform;
  final String flavor;
  final int maxPerRun;

  /// The reporter of the connected business; null before connecting.
  static ErrorReporter? instance;

  /// Reports through [instance], if any. Never throws.
  static void reportError(Object error, StackTrace? stack) => instance?.report(error, stack);

  static const maxBytes = 16 * 1024;
  static const _maxMessage = 2000;

  final Set<String> _seen = {};
  int _sent = 0;

  @visibleForTesting
  int get sentCount => _sent;

  void report(Object error, StackTrace? stack) {
    try {
      if (_sent >= maxPerRun || !signedIn()) return;
      final body = buildBody(error, stack);
      if (!_seen.add(body['message']!)) return;
      _sent++;
      // A failed send is dropped, never reported again.
      unawaited(Future.sync(() => post(body)).catchError((Object _) {}));
    } catch (_) {
      // Reporting must never add an error of its own.
    }
  }

  @visibleForTesting
  Map<String, String> buildBody(Object error, StackTrace? stack) {
    final message = _clip(scrub(error.toString()), _maxMessage);
    final base = {'message': message, 'stack': '', 'app_version': appVersion, 'platform': platform, 'flavor': flavor};
    // Room left for the stack once everything else is encoded (with a margin
    // for JSON escaping of the stack itself).
    final room = maxBytes - utf8.encode(jsonEncode(base)).length - 64;
    var trace = scrub(stack?.toString() ?? '');
    while (trace.isNotEmpty && utf8.encode(jsonEncode(trace)).length > room) {
      trace = trace.substring(0, (trace.length * 0.8).floor());
    }
    return {...base, 'stack': trace};
  }

  static String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}…';

  static final _bearer = RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false);
  static final _jwt = RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)?');
  static final _secretField = RegExp(
    r'(access_token|refresh_token|password|apikey|api_key)(["\x27]?\s*[:=]\s*["\x27]?)[^\s,&"\x27}]+',
    caseSensitive: false,
  );

  /// Removes anything that looks like a token or password from [text].
  static String scrub(String text) {
    final out = text
        .replaceAll(_bearer, 'Bearer [removed]')
        .replaceAll(_jwt, '[removed]')
        .replaceAllMapped(_secretField, (m) => '${m[1]}${m[2]}[removed]');
    return out;
  }
}
