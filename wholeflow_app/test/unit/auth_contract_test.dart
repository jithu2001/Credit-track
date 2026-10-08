import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wholeflow_app/core/errors/app_failure.dart';

/// The app's login library (gotrue, inside supabase_flutter) against the
/// answers the WholeFlow app API gives for signing in
/// (test/fixtures/api/auth_*.json, written by the Go integration test). The
/// server replaced GoTrue; this proves the app needs no change.
void main() {
  late List<http.Request> sent;
  GoTrueClient client({required bool wrongPassword}) {
    sent = [];
    return GoTrueClient(
      url: 'https://api.example.test/b/apitest/auth/v1',
      autoRefreshToken: false,
      httpClient: MockClient((req) async {
        sent.add(req);
        final path = req.url.path.split('/auth/v1/').last;
        final grant = req.url.queryParameters['grant_type'];
        final (name, status) = switch ((req.method, path, grant)) {
          ('POST', 'token', 'password') when wrongPassword => ('auth_error', 400),
          ('POST', 'token', _) => ('auth_token', 200),
          ('PUT', 'user', _) => ('auth_user', 200),
          ('POST', 'logout', _) => ('', 204),
          _ => ('', 404),
        };
        if (name.isEmpty) return http.Response('', status);
        return http.Response.bytes(
          File('test/fixtures/api/$name.json').readAsBytesSync(),
          status,
          headers: {'content-type': 'application/json', 'x-supabase-api-version': '2024-01-01'},
        );
      }),
    );
  }

  test('sign in: the session and user are read as before', () async {
    final auth = client(wrongPassword: false);
    final res = await auth.signInWithPassword(email: 'o@a.test', password: 'owner-pass-1');
    expect(res.session!.accessToken, isNotEmpty);
    expect(res.session!.refreshToken, isNotEmpty);
    expect(res.user!.email, 'o@a.test');
    expect(sent.single.url.queryParameters['grant_type'], 'password');
  });

  test('a wrong password is "Wrong email or password."', () async {
    final auth = client(wrongPassword: true);
    try {
      await auth.signInWithPassword(email: 'o@a.test', password: 'nope');
      fail('should throw');
    } on AuthException catch (e) {
      expect(e.code, 'invalid_credentials');
      expect(AppFailure.from(e).kind, FailureKind.invalidCredentials);
    }
  });

  test('changing the password clears must_change_password (the app reads it)', () async {
    final auth = client(wrongPassword: false);
    await auth.signInWithPassword(email: 'o@a.test', password: 'owner-pass-1');
    // The app sends only the password; the server clears the flag itself.
    final res = await auth.updateUser(UserAttributes(password: 'owner-pass-2'));
    expect(res.user!.userMetadata?['must_change_password'], isNot(true));
    expect(auth.currentUser!.userMetadata?['must_change_password'], isNot(true));
    expect(sent.last.method, 'PUT');
  });

  test('refresh returns a session the library accepts', () async {
    final auth = client(wrongPassword: false);
    await auth.signInWithPassword(email: 'o@a.test', password: 'owner-pass-1');
    final res = await auth.refreshSession();
    expect(res.session!.accessToken, isNotEmpty);
    expect(sent.last.url.queryParameters['grant_type'], 'refresh_token');
  });
}
