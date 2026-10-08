import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_client.dart';

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
    if (error is PostgrestException) return _fromPostgrest(error);
    if (error is ApiException) return _fromApi(error);
    if (error is FunctionException) return _fromFunction(error);
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

  static AppFailure _fromPostgrest(PostgrestException e) {
    final code = e.code ?? '';
    if (code == 'PT402' || code == '402' || e.message.contains('subscription_ended')) {
      var details = e.details, hint = e.hint;
      // `.maybeSingle()` re-wraps errors: code becomes the HTTP status and the
      // server's JSON is left as text in the message.
      if (code == '402') {
        try {
          final body = jsonDecode(e.message);
          if (body is Map) (details, hint) = (body['details'], body['hint']);
        } catch (_) {}
      }
      final f = AppFailure(FailureKind.subscriptionEnded, _text(details), _text(hint));
      onSubscriptionEnded?.call(f);
      return f;
    }
    if (code == 'PGRST301' || code == 'PGRST303' || e.message.contains('JWT expired')) {
      return const AppFailure(FailureKind.unauthenticated);
    }
    if (code == '42501') return const AppFailure(FailureKind.forbidden);
    if (code == 'PGRST116') return const AppFailure(FailureKind.notFound);
    if (code.startsWith('5') || code.startsWith('XX')) return const AppFailure(FailureKind.server);
    return const AppFailure(FailureKind.unknown);
  }

  /// The WholeFlow app API (core/api/api_client.dart).
  static AppFailure _fromApi(ApiException e) {
    switch (e.status) {
      case 402:
        final f = AppFailure(FailureKind.subscriptionEnded, _text(e.details), _text(e.hint));
        onSubscriptionEnded?.call(f);
        return f;
      case 401:
        return const AppFailure(FailureKind.unauthenticated);
      case 403:
        return AppFailure(FailureKind.forbidden, e.code == 'FORBIDDEN' ? null : _text(e.message));
      case 404:
        return const AppFailure(FailureKind.notFound);
      case 400:
        return AppFailure(FailureKind.invalidInput, _text(e.message));
    }
    return e.status >= 500 ? const AppFailure(FailureKind.server) : const AppFailure(FailureKind.unknown);
  }

  static String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

  /// manage-staff returns `{ "error": { "code", "message" } }`.
  static AppFailure _fromFunction(FunctionException e) {
    final details = e.details;
    String? code;
    String? message;
    if (details is Map && details['error'] is Map) {
      code = details['error']['code'] as String?;
      message = details['error']['message'] as String?;
    }
    switch (code) {
      case 'UNAUTHENTICATED':
        return const AppFailure(FailureKind.unauthenticated);
      case 'NOT_OWNER':
        return AppFailure(FailureKind.forbidden, message);
      case 'INVALID_INPUT':
        return AppFailure(FailureKind.invalidInput, message);
      case 'EMAIL_TAKEN':
        return const AppFailure(FailureKind.emailTaken);
      case 'NOT_FOUND':
        return AppFailure(FailureKind.notFound, message);
    }
    if (e.status == 401) return const AppFailure(FailureKind.unauthenticated);
    if (e.status == 402) {
      const f = AppFailure(FailureKind.subscriptionEnded);
      onSubscriptionEnded?.call(f);
      return f;
    }
    if (e.status >= 500) return const AppFailure(FailureKind.server);
    return const AppFailure(FailureKind.unknown);
  }
}
