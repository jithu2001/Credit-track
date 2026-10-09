import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../data/auth_repository.dart';
import '../domain/app_user.dart';

part 'session_controller.g.dart';

sealed class Session {
  const Session();
}

class SignedOut extends Session {
  const SignedOut({this.message});

  /// Why the user was signed out (e.g. account disabled), shown on the login screen.
  final String? message;
}

class SignedIn extends Session {
  const SignedIn(this.user, {this.mustChangePassword = false});

  final AppUser user;
  final bool mustChangePassword;
}

/// Signed in, but the business's WholeFlow subscription has ended (or was
/// suspended): the server refuses every data request, so the app shows only
/// the paused screen with [message] and [contact] until it is renewed.
class Paused extends Session {
  const Paused({this.message, this.contact});

  final String? message;
  final String? contact;
}

/// The app's single source of truth for who is signed in.
///
/// A session only counts as signed in once the caller's `public.users` row is
/// loaded and active; otherwise the login session is dropped.
@Riverpod(keepAlive: true)
class SessionController extends _$SessionController {
  StreamSubscription<AuthState>? _sub;

  /// True while this controller drops the session itself, so the resulting
  /// `signedOut` event doesn't replace the message it is about to show.
  bool _signingOut = false;

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<Session> build() async {
    final repo = ref.watch(authRepositoryProvider);
    await _sub?.cancel();
    _sub = repo.authStateChanges().listen(_onAuthEvent, onError: (_) {});
    AppFailure.onSubscriptionEnded = _onSubscriptionEnded;
    AppFailure.onSessionEnded = _onSessionEnded;
    ref.onDispose(() {
      _sub?.cancel();
      if (AppFailure.onSubscriptionEnded == _onSubscriptionEnded) AppFailure.onSubscriptionEnded = null;
      if (AppFailure.onSessionEnded == _onSessionEnded) AppFailure.onSessionEnded = null;
    });
    return _resolve();
  }

  /// Any screen's request was refused with HTTP 402. Deferred: errors are
  /// also mapped while widgets build.
  void _onSubscriptionEnded(AppFailure f) => scheduleMicrotask(() => _pause(f));

  /// Any screen's request was refused with HTTP 401: the session was ended on
  /// the server. Deferred like [_onSubscriptionEnded].
  void _onSessionEnded() => scheduleMicrotask(() async {
    if (!ref.mounted || _signingOut) return;
    final current = state.value;
    if (current is! SignedIn && current is! Paused) return;
    await signOut(message: sessionEndedMessage);
  });

  void _pause(AppFailure f) {
    if (!ref.mounted || !_repo.hasSession) return;
    final current = state.value;
    if (current is Paused && current.message == f.detail && current.contact == f.contact) return;
    // A 402 from a function call carries no text; keep the text we have.
    if (current is Paused && f.detail == null) return;
    state = AsyncData(Paused(message: f.detail, contact: f.contact));
  }

  Future<Session> _resolve() async {
    if (!_repo.hasSession) return const SignedOut();
    final AppUser? user;
    try {
      user = await _repo.loadProfile();
    } on AppFailure catch (f) {
      if (f.kind == FailureKind.subscriptionEnded) return Paused(message: f.detail, contact: f.contact);
      if (f.kind == FailureKind.unauthenticated) {
        await _dropSession();
        return const SignedOut(message: sessionEndedMessage);
      }
      rethrow;
    }
    if (user == null || !user.isActive) {
      await _dropSession();
      return const SignedOut(message: inactiveAccountMessage);
    }
    return SignedIn(user, mustChangePassword: _repo.mustChangePassword);
  }

  Future<void> _dropSession() async {
    _signingOut = true;
    try {
      await _repo.signOut();
    } finally {
      _signingOut = false;
    }
  }

  void _onAuthEvent(AuthState event) {
    switch (event.event) {
      case AuthChangeEvent.signedOut:
        // Signed out elsewhere: refresh token revoked, account banned, etc.
        if (!_signingOut && (state.value is SignedIn || state.value is Paused)) {
          state = const AsyncData(SignedOut(message: sessionEndedMessage));
        }
      case AuthChangeEvent.userUpdated:
        final current = state.value;
        if (current is SignedIn) {
          state = AsyncData(SignedIn(current.user, mustChangePassword: _repo.mustChangePassword));
        }
      default:
        break;
    }
  }

  Future<void> signIn(String email, String password) async {
    await _repo.signIn(email: email, password: password);
    final session = await _resolve();
    state = AsyncData(session);
    if (session is SignedOut && session.message != null) {
      throw AppFailure(FailureKind.forbidden, session.message);
    }
  }

  Future<void> signOut({String? message}) async {
    await _dropSession();
    state = AsyncData(SignedOut(message: message));
  }

  /// [currentPassword]: see [AuthRepository.changePassword]. Afterwards the
  /// user's flags are read from the server's answer.
  Future<void> changePassword(String newPassword, {String? currentPassword}) async {
    await _repo.changePassword(newPassword, currentPassword: currentPassword);
    final current = state.value;
    if (current is SignedIn) state = AsyncData(SignedIn(current.user, mustChangePassword: _repo.mustChangePassword));
  }

  /// Re-reads the caller's row (on resume and refresh) so a disabled account
  /// is signed out promptly, even while its access token is still valid.
  Future<void> revalidate() async {
    final current = state.value;
    if (current is Paused) return retry();
    if (current is! SignedIn) return;
    try {
      final user = await _repo.loadProfile();
      if (user == null || !user.isActive) {
        await signOut(message: inactiveAccountMessage);
      } else if (user != current.user) {
        state = AsyncData(SignedIn(user, mustChangePassword: current.mustChangePassword));
      }
    } on AppFailure catch (f) {
      if (f.kind == FailureKind.unauthenticated) await signOut(message: f.message);
      // subscriptionEnded: already handled by _onSubscriptionEnded.
      // Network errors: keep the session; screens show their own error states.
    }
  }

  /// Retry after a start-up failure (e.g. offline when the app opened), and
  /// the paused screen's Refresh.
  Future<void> retry() async {
    final previous = state.value;
    // While paused, stay on the paused screen (it shows its own progress).
    if (previous is! Paused) state = const AsyncLoading();
    final next = await AsyncValue.guard(_resolve);
    state = next.hasError && previous is Paused ? AsyncData(previous) : next;
  }
}

/// The signed-in user; null while signed out (screens can rebuild for a frame
/// during sign-out before the router moves to the login screen).
@riverpod
AppUser? currentUser(Ref ref) {
  final session = ref.watch(sessionControllerProvider).value;
  return session is SignedIn ? session.user : null;
}
