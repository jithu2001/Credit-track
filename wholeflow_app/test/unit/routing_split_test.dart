import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wholeflow_app/core/router/owner_router.dart';
import 'package:wholeflow_app/core/router/staff_router.dart';
import 'package:wholeflow_app/features/auth/domain/app_user.dart';
import 'package:wholeflow_app/features/auth/presentation/session_controller.dart';
import 'package:wholeflow_app/features/home/staff_home_shell.dart';

const ownerUser = AppUser(id: 'o', businessId: 'b', role: UserRole.owner, name: 'Owner');
const staffUser = AppUser(id: 's', businessId: 'b', role: UserRole.staff, name: 'Staff');

void main() {
  group('Owner App Routing', () {
    test('SignedOut redirects to /login', () {
      expect(ownerRedirectFor(const AsyncData(SignedOut()), '/dashboard'), '/login');
      expect(ownerRedirectFor(const AsyncData(SignedOut()), '/login'), isNull);
    });

    test('Staff user in Owner App gets redirected to /not-owner', () {
      expect(ownerRedirectFor(const AsyncData(SignedIn(staffUser)), '/dashboard'), '/not-owner');
      expect(ownerRedirectFor(const AsyncData(SignedIn(staffUser)), '/not-owner'), isNull);
    });

    test('Owner user in Owner App gets full access', () {
      expect(ownerRedirectFor(const AsyncData(SignedIn(ownerUser)), '/dashboard'), isNull);
      expect(ownerRedirectFor(const AsyncData(SignedIn(ownerUser)), '/login'), '/dashboard');
      expect(ownerRedirectFor(const AsyncData(SignedIn(ownerUser)), '/analytics'), isNull);
      expect(ownerRedirectFor(const AsyncData(SignedIn(ownerUser)), '/staff'), isNull);
      expect(ownerRedirectFor(const AsyncData(SignedIn(ownerUser)), '/purchases/1'), isNull);
    });

    test('Force password change redirects to /change-password', () {
      expect(ownerRedirectFor(const AsyncData(SignedIn(ownerUser, mustChangePassword: true)), '/dashboard'), '/change-password');
    });
  });

  group('Staff App Routing', () {
    test('navigation items have 3 tabs: Dashboard, Shops, Inventory', () {
      expect(staffNavItems.map((i) => i.label), ['Dashboard', 'Shops', 'Inventory']);
    });

    test('SignedOut redirects to /login', () {
      expect(staffRedirectFor(const AsyncData(SignedOut()), '/dashboard'), '/login');
      expect(staffRedirectFor(const AsyncData(SignedOut()), '/login'), isNull);
    });

    test('Staff user in Staff App gets access to staff dashboard', () {
      expect(staffRedirectFor(const AsyncData(SignedIn(staffUser)), '/dashboard'), isNull);
      expect(staffRedirectFor(const AsyncData(SignedIn(staffUser)), '/login'), '/dashboard');
      expect(staffRedirectFor(const AsyncData(SignedIn(staffUser)), '/inventory'), isNull);
      expect(staffRedirectFor(const AsyncData(SignedIn(staffUser)), '/shops'), isNull);
    });

    test('Owner user in Staff App gets redirected to /not-staff', () {
      expect(staffRedirectFor(const AsyncData(SignedIn(ownerUser)), '/dashboard'), '/not-staff');
      expect(staffRedirectFor(const AsyncData(SignedIn(ownerUser)), '/stock/item/1'), '/not-staff');
      expect(staffRedirectFor(const AsyncData(SignedIn(ownerUser)), '/not-staff'), isNull);
    });

    test('Force password change redirects to /change-password', () {
      expect(staffRedirectFor(const AsyncData(SignedIn(staffUser, mustChangePassword: true)), '/dashboard'), '/change-password');
    });
  });
}
