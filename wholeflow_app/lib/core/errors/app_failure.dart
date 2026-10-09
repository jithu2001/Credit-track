import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_client.dart';
import '../upgrade/upgrade_gate.dart';

enum FailureKind {
  network,
  unauthenticated,
  invalidCredentials,
  forbidden,
  notFound,
  invalidInput,
  emailTaken,
  server,
  subscriptionEnded,

  /// This app version is too old for the server (HTTP 426); the app shows
  /// only the "Update required" screen.
  upgradeRequired,

  /// Changing the password needs a fresh sign-in (the server's
  /// `reauthentication_needed`).
  reauthenticationNeeded,
  unknown,
}

/// Every error shown to the user goes through this type, so screens only deal
/// with friendly copy and never with the API client's exceptions.
class AppFailure implements Exception {
  const AppFailure(this.kind, [this.detail, this.contact]);

  final FailureKind kind;

  /// Server-provided, user-safe text (e.g. validation messages from manage-staff,
  /// or how to renew when the subscription has ended).
  final String? detail;

  /// For [FailureKind.subscriptionEnded]: who to contact (phone / UPI id).
  final String? contact;

  /// Called whenever a request is refused because the business's subscription
  /// has ended (HTTP 402 from the data API), wherever it happened. The session
  /// controller uses it to switch to the "paused" screen at once.
  static void Function(AppFailure failure)? onSubscriptionEnded;

  /// Called whenever the app API refuses the access token (HTTP 401: signed
  /// out elsewhere, password reset, account disabled). The session controller
  /// uses it to go back to the sign-in screen at once.
  static void Function()? onSessionEnded;

  String get message => switch (kind) {
    FailureKind.network => 'No internet connection. Check your network and try again.',
    FailureKind.unauthenticated => 'Your session has ended. Please sign in again.',
    FailureKind.invalidCredentials => 'Wrong email or password.',
    FailureKind.forbidden => detail ?? "You don't have access to this.",
    FailureKind.notFound => detail ?? 'This item is no longer available.',
    FailureKind.invalidInput => detail ?? 'Please check the details and try again.',
    FailureKind.emailTaken => 'An account with this email already exists.',
    FailureKind.server => 'The server had a problem. Please try again in a moment.',
    FailureKind.subscriptionEnded => 'WholeFlow is paused for this business.',
    FailureKind.upgradeRequired => detail ?? UpgradeGate.defaultMessage,
    FailureKind.reauthenticationNeeded => 'For your security, please sign in again, then change your password.',
    FailureKind.unknown => 'Something went wrong. Please try again.',
  };

  @override
  String toString() => 'AppFailure($kind${detail == null ? '' : ': $detail'})';

  /// Maps any thrown error to an [AppFailure].
  static AppFailure from(Object error) {
    if (error is AppFailure) return error;
    if (error is SocketException || error is TimeoutException || error is HandshakeException) {
      return const AppFailure(FailureKind.network);
    }
    if (error is AuthException) return _fromAuth(error);
    if (error is ApiException) return _fromApi(error);
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('Failed host lookup') ||
        text.contains('Connection refused')) {
      return const AppFailure(FailureKind.network);
    }
    return const AppFailure(FailureKind.unknown);
  }

  static AppFailure _fromAuth(AuthException e) {
    final code = e.code ?? '';
    if (code == 'upgrade_required' || e.statusCode == '426') {
      final f = AppFailure(FailureKind.upgradeRequired, _text(e.message));
      UpgradeGate.trigger(f.detail);
      return f;
    }
    if (code == 'reauthentication_needed') return const AppFailure(FailureKind.reauthenticationNeeded);
    if (e is AuthRetryableFetchException) return const AppFailure(FailureKind.network);
    if (code == 'invalid_credentials' || e.message.toLowerCase().contains('invalid login credentials')) {
      return const AppFailure(FailureKind.invalidCredentials);
    }
    if (code == 'user_banned') {
      return const AppFailure(FailureKind.forbidden, 'Your account is not active. Contact your business owner.');
    }
    if (code == 'weak_password' || code == 'same_password') {
      return AppFailure(
        FailureKind.invalidInput,
        code == 'same_password' ? 'Choose a password different from the current one.' : 'Choose a stronger password.',
      );
    }
    if (code == 'session_not_found' || code == 'refresh_token_not_found' || e.statusCode == '401') {
      return const AppFailure(FailureKind.unauthenticated);
    }
    return const AppFailure(FailureKind.unknown);
  }

  /// The WholeFlow app API (core/api/api_client.dart).
  static AppFailure _fromApi(ApiException e) {
    switch (e.status) {
      case 402:
        final f = AppFailure(FailureKind.subscriptionEnded, _text(e.details), _text(e.hint));
        onSubscriptionEnded?.call(f);
        return f;
      case 426:
        final f = AppFailure(FailureKind.upgradeRequired, _text(e.message));
        UpgradeGate.trigger(f.detail);
        return f;
      case 401:
        onSessionEnded?.call();
        return const AppFailure(FailureKind.unauthenticated);
      case 403:
        return AppFailure(FailureKind.forbidden, e.code == 'FORBIDDEN' ? null : _text(e.message));
      case 404:
        return const AppFailure(FailureKind.notFound);
      case 409 when e.code == 'EMAIL_TAKEN':
        return const AppFailure(FailureKind.emailTaken);
      case 400:
      case 409:
        return AppFailure(FailureKind.invalidInput, _text(e.message));
    }
    return e.status >= 500 ? const AppFailure(FailureKind.server) : const AppFailure(FailureKind.unknown);
  }

  static String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
}
