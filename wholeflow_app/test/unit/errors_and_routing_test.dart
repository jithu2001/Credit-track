import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wholeflow_app/core/api/api_client.dart';
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

    test('app API errors', () {
      expect(AppFailure.from(const ApiException(401, 'UNAUTHENTICATED', 'Sign in again.')).kind, FailureKind.unauthenticated);
      expect(AppFailure.from(const ApiException(403, 'FORBIDDEN', 'x')).kind, FailureKind.forbidden);
      expect(AppFailure.from(const ApiException(404, 'NOT_FOUND', 'x')).kind, FailureKind.notFound);
    });

    test('staff management errors', () {
      expect(AppFailure.from(const ApiException(409, 'EMAIL_TAKEN', 'm')).kind, FailureKind.emailTaken);
      final invalid = AppFailure.from(const ApiException(400, 'INVALID_INPUT', 'Assign at least one company.'));
      expect(invalid.kind, FailureKind.invalidInput);
      expect(invalid.message, 'Assign at least one company.');
      final notOwner = AppFailure.from(const ApiException(403, 'NOT_OWNER', 'Only the business owner can manage staff.'));
      expect(notOwner.kind, FailureKind.forbidden);
      expect(notOwner.message, 'Only the business owner can manage staff.');
      expect(
        AppFailure.from(const ApiException(409, 'NAME_TAKEN', 'There is already a site with this name.')).message,
        'There is already a site with this name.',
      );
      expect(AppFailure.from(const ApiException(502, 'HTTP_502', 'm')).kind, FailureKind.server);
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
