import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

enum FailureKind { network, unauthenticated, invalidCredentials, forbidden, notFound, invalidInput, emailTaken, server, unknown }

/// Every error shown to the user goes through this type, so screens only deal
/// with friendly copy and never with Supabase exceptions.
class AppFailure implements Exception {
  const AppFailure(this.kind, [this.detail]);

  final FailureKind kind;

  /// Server-provided, user-safe text (e.g. validation messages from manage-staff).
  final String? detail;

  String get message => switch (kind) {
    FailureKind.network => 'No internet connection. Check your network and try again.',
    FailureKind.unauthenticated => 'Your session has ended. Please sign in again.',
    FailureKind.invalidCredentials => 'Wrong email or password.',
    FailureKind.forbidden => detail ?? "You don't have access to this.",
    FailureKind.notFound => detail ?? 'This item is no longer available.',
    FailureKind.invalidInput => detail ?? 'Please check the details and try again.',
    FailureKind.emailTaken => 'An account with this email already exists.',
    FailureKind.server => 'The server had a problem. Please try again in a moment.',
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
    if (code == 'PGRST301' || code == 'PGRST303' || e.message.contains('JWT expired')) {
      return const AppFailure(FailureKind.unauthenticated);
    }
    if (code == '42501') return const AppFailure(FailureKind.forbidden);
    if (code == 'PGRST116') return const AppFailure(FailureKind.notFound);
    if (code.startsWith('5') || code.startsWith('XX')) return const AppFailure(FailureKind.server);
    return const AppFailure(FailureKind.unknown);
  }

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
    if (e.status >= 500) return const AppFailure(FailureKind.server);
    return const AppFailure(FailureKind.unknown);
  }
}
