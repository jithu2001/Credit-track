import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wholeflow_app/core/api/api_client.dart';
import 'package:wholeflow_app/core/errors/app_failure.dart';
import 'package:wholeflow_app/core/theme/app_theme.dart';
import 'package:wholeflow_app/core/upgrade/update_required_screen.dart';
import 'package:wholeflow_app/core/upgrade/upgrade_gate.dart';
import 'package:wholeflow_app/features/auth/data/auth_repository.dart';
import 'package:wholeflow_app/features/auth/presentation/auth_screens.dart';
import 'package:wholeflow_app/features/auth/presentation/session_controller.dart';
import 'package:wholeflow_app/features/settings/presentation/settings_screen.dart';

import 'helpers.dart';

void main() {
  setUp(UpgradeGate.reset);

  group('update required', () {
    testWidgets('any request refused with 426 replaces the app with the update screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => UpdateRequiredFrame(child: child!),
          home: const Scaffold(body: Text('dashboard')),
        ),
      );
      expect(find.text('dashboard'), findsOneWidget);
      expect(find.byKey(const Key('update-required')), findsNothing);

      // E.g. a screen's load failed with HTTP 426.
      AppFailure.from(const ApiException(426, 'UPGRADE_REQUIRED', 'Update WholeFlow to keep using it.'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-required')), findsOneWidget);
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Update WholeFlow to keep using it.'), findsOneWidget);
      expect(find.byKey(const Key('update-open-store')), findsOneWidget);
      expect(find.text('dashboard'), findsNothing);
    });
  });

  group('passwords', () {
    Future<ProviderContainer> pump(WidgetTester tester, Widget screen, FakeAuthRepository repo) async {
      await pumpScreen(tester, screen, overrides: [authRepositoryProvider.overrideWithValue(repo)]);
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byWidget(screen)));
    }

    testWidgets('Settings asks for the current password and passes it on', (tester) async {
      final repo = FakeAuthRepository(profile: staffUser)..signedIn = true;
      await pump(tester, const Scaffold(body: ChangePasswordSheet()), repo);
      await tester.tap(find.text('Change password').last);
      await tester.pump();
      expect(find.text('Enter your current password'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('current-password')), 'old-pass-1');
      await tester.enterText(find.byKey(const Key('new-password')), 'short');
      await tester.enterText(find.byKey(const Key('confirm-password')), 'short');
      await tester.tap(find.text('Change password').last);
      await tester.pump();
      expect(find.text('Use at least 8 characters'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('new-password')), 'new-pass-22');
      await tester.enterText(find.byKey(const Key('confirm-password')), 'new-pass-22');
      await tester.tap(find.text('Change password').last);
      await tester.pumpAndSettle();
      expect(repo.passwordChanges.single, ('new-pass-22', 'old-pass-1'));
    });

    testWidgets('Settings: a wrong current password is shown', (tester) async {
      final repo = FakeAuthRepository(profile: staffUser)
        ..signedIn = true
        ..changePasswordError = const AppFailure(FailureKind.invalidInput, wrongCurrentPassword);
      await pump(tester, const Scaffold(body: ChangePasswordSheet()), repo);
      await tester.enterText(find.byKey(const Key('current-password')), 'nope');
      await tester.enterText(find.byKey(const Key('new-password')), 'new-pass-22');
      await tester.enterText(find.byKey(const Key('confirm-password')), 'new-pass-22');
      await tester.tap(find.text('Change password').last);
      await tester.pumpAndSettle();
      expect(find.text('Current password is wrong.'), findsOneWidget);
    });

    testWidgets('first sign-in: no current password; a too-old session goes back to sign in', (tester) async {
      final repo = FakeAuthRepository(profile: staffUser)
        ..signedIn = true
        ..changePasswordError = const AppFailure(FailureKind.reauthenticationNeeded);
      final container = await pump(tester, const ForcePasswordChangeScreen(), repo);
      expect(find.byKey(const Key('current-password')), findsNothing);
      await tester.enterText(find.byKey(const Key('new-password')), 'new-pass-22');
      await tester.enterText(find.byKey(const Key('confirm-password')), 'new-pass-22');
      await tester.tap(find.text('Save and continue'));
      await tester.pumpAndSettle();
      expect(repo.signedIn, isFalse);
      final session = container.read(sessionControllerProvider).value;
      expect(session, isA<SignedOut>().having((s) => s.message, 'message', contains('sign in again')));
    });
  });
}
