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

/// The app's single source of truth for who is signed in.
///
/// A session only counts as signed in once the caller's `public.users` row is
/// loaded and active; otherwise the Supabase session is dropped.
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
    ref.onDispose(() => _sub?.cancel());
    return _resolve();
  }

  Future<Session> _resolve() async {
    if (!_repo.hasSession) return const SignedOut();
    final user = await _repo.loadProfile();
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
        if (!_signingOut && state.value is SignedIn) {
          state = const AsyncData(SignedOut(message: 'Your session has ended. Please sign in again.'));
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

  Future<void> changePassword(String newPassword) async {
    await _repo.changePassword(newPassword);
    final current = state.value;
    if (current is SignedIn) state = AsyncData(SignedIn(current.user));
  }

  /// Re-reads the caller's row (on resume and refresh) so a disabled account
  /// is signed out promptly, even while its access token is still valid.
  Future<void> revalidate() async {
    final current = state.value;
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
      // Network errors: keep the session; screens show their own error states.
    }
  }

  /// Retry after a start-up failure (e.g. offline when the app opened).
  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_resolve);
  }
}

/// The signed-in user; null while signed out (screens can rebuild for a frame
/// during sign-out before the router moves to the login screen).
@riverpod
AppUser? currentUser(Ref ref) {
  final session = ref.watch(sessionControllerProvider).value;
  return session is SignedIn ? session.user : null;
}
