import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wholeflow_app/core/errors/app_failure.dart';
import 'package:wholeflow_app/core/router/app_router.dart';
import 'package:wholeflow_app/features/auth/domain/app_user.dart';
import 'package:wholeflow_app/features/auth/presentation/session_controller.dart';
import 'package:wholeflow_app/features/home/home_shell.dart';

const owner = AppUser(id: 'o', businessId: 'b', role: UserRole.owner, name: 'Owner');
const staff = AppUser(id: 's', businessId: 'b', role: UserRole.staff, name: 'Staff');

void main() {
  group('AppFailure.from', () {
    test('network', () {
      expect(AppFailure.from(const SocketException('x')).kind, FailureKind.network);
    });

    test('auth', () {
      expect(
        AppFailure.from(const AuthException('Invalid login credentials', code: 'invalid_credentials')).kind,
        FailureKind.invalidCredentials,
      );
      expect(
        AppFailure.from(const AuthException('banned', code: 'user_banned')).message,
        'Your account is not active. Contact your business owner.',
      );
    });

    test('postgrest', () {
      expect(
        AppFailure.from(const PostgrestException(message: 'JWT expired', code: 'PGRST301')).kind,
        FailureKind.unauthenticated,
      );
      expect(AppFailure.from(const PostgrestException(message: 'denied', code: '42501')).kind, FailureKind.forbidden);
    });

    test('manage-staff error codes', () {
      FunctionException fx(int status, String code, [String message = 'm']) => FunctionException(
        status: status,
        details: {
          'error': {'code': code, 'message': message},
        },
      );
      expect(AppFailure.from(fx(409, 'EMAIL_TAKEN')).kind, FailureKind.emailTaken);
      final invalid = AppFailure.from(fx(400, 'INVALID_INPUT', 'Assign at least one company.'));
      expect(invalid.kind, FailureKind.invalidInput);
      expect(invalid.message, 'Assign at least one company.');
      expect(AppFailure.from(fx(403, 'NOT_OWNER')).kind, FailureKind.forbidden);
      expect(AppFailure.from(const FunctionException(status: 502)).kind, FailureKind.server);
    });
  });

  group('navigation by role', () {
    test('Analytics and Staff tabs are owner-only', () {
      expect(navItemsFor(UserRole.owner).map((i) => i.label), ['Dashboard', 'Shops', 'Outstanding', 'Analytics', 'Staff']);
      expect(navItemsFor(UserRole.staff).map((i) => i.label), ['Dashboard', 'Shops', 'Outstanding']);
    });

    test('redirects', () {
      expect(redirectFor(const AsyncLoading(), '/dashboard'), '/splash');
      expect(redirectFor(const AsyncData(SignedOut()), '/dashboard'), '/login');
      expect(redirectFor(const AsyncData(SignedOut()), '/login'), isNull);
      expect(redirectFor(const AsyncData(SignedIn(owner, mustChangePassword: true)), '/dashboard'), '/change-password');
      expect(redirectFor(const AsyncData(SignedIn(owner)), '/login'), '/dashboard');
      expect(redirectFor(const AsyncData(SignedIn(owner)), '/staff/new'), isNull);
      expect(redirectFor(const AsyncData(SignedIn(staff)), '/staff'), '/dashboard');
      expect(redirectFor(const AsyncData(SignedIn(staff)), '/staff/abc/edit'), '/dashboard');
      expect(redirectFor(const AsyncData(SignedIn(staff)), '/sync-health'), '/dashboard');
      expect(redirectFor(const AsyncData(SignedIn(staff)), '/shop/1'), isNull);
      expect(redirectFor(const AsyncData(SignedIn(staff)), '/analytics'), '/dashboard');
      expect(redirectFor(const AsyncData(SignedIn(staff)), '/analytics/shop/1'), '/dashboard');
      expect(redirectFor(const AsyncData(SignedIn(owner)), '/analytics'), isNull);
      expect(redirectFor(const AsyncData(SignedIn(staff)), '/settings'), isNull);
    });
  });
}
