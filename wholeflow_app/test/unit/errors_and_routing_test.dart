import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wholeflow_app/core/errors/app_failure.dart';
import 'package:wholeflow_app/features/auth/domain/app_user.dart';
import 'package:wholeflow_app/features/home/home_shell.dart';

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
    test('owners get Sites and Stock; staff get the Stock tab as Inventory', () {
      expect(navItemsFor(UserRole.owner).map((i) => i.label), ['Dashboard', 'Shops', 'Sites', 'Stock']);
      expect(navItemsFor(UserRole.staff).map((i) => i.label), ['Dashboard', 'Shops', 'Inventory']);
      expect(navItemsFor(UserRole.staff).last.branch, Branch.stock);
    });
  });
}
