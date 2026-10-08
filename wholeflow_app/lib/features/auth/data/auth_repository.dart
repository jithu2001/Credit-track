import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/providers.dart';
import '../domain/app_user.dart';

part 'auth_repository.g.dart';

const inactiveAccountMessage = 'Your account is not active. Contact your business owner.';
const sessionEndedMessage = 'Your session has ended. Please sign in again.';
const wrongCurrentPassword = 'Current password is wrong.';

/// Signing in and passwords go to the business's login service; the
/// profile comes from the app API.
class AuthRepository {
  AuthRepository(this._client, this._api);

  final SupabaseClient _client;
  final ApiClient _api;

  Stream<AuthState> authStateChanges() => _client.auth.onAuthStateChange;

  bool get hasSession => _client.auth.currentSession != null;

  /// Set by the manage-staff function on new staff and after a password reset.
  bool get mustChangePassword => _client.auth.currentUser?.userMetadata?['must_change_password'] == true;

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email.trim().toLowerCase(), password: password);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Offline sign-out still clears the local session.
    }
  }

  /// The caller's own `users` row, or null when there is none.
  Future<AppUser?> loadProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = (await _api.get('me'))['user'];
      return row is Map<String, dynamic> ? AppUser.fromJson(row) : null;
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Sets a new password. The server clears `must_change_password` itself
  /// and answers with the updated user, which the login library keeps (so
  /// [mustChangePassword] is read fresh afterwards).
  ///
  /// With [currentPassword] (Settings → Change password), signs in with it
  /// first: the server only accepts a password change from a session made in
  /// the last few minutes. The first-sign-in screen passes none; its session
  /// is new already.
  Future<void> changePassword(String newPassword, {String? currentPassword}) async {
    if (currentPassword != null) {
      final email = _client.auth.currentUser?.email;
      if (email == null) throw const AppFailure(FailureKind.unauthenticated);
      try {
        await _client.auth.signInWithPassword(email: email, password: currentPassword);
      } catch (e) {
        final f = AppFailure.from(e);
        if (f.kind == FailureKind.invalidCredentials) throw const AppFailure(FailureKind.invalidInput, wrongCurrentPassword);
        throw f;
      }
    }
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<String?> businessName(String businessId) async {
    try {
      return (await _api.get('me'))['business_name'] as String?;
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) => AuthRepository(ref.watch(supabaseProvider), ref.watch(apiClientProvider));
