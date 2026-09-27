import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wholeflow_app/core/errors/app_failure.dart';
import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/core/providers.dart';
import 'package:wholeflow_app/core/theme/app_theme.dart';
import 'package:wholeflow_app/core/widgets/balance_text.dart';
import 'package:wholeflow_app/features/auth/data/auth_repository.dart';
import 'package:wholeflow_app/features/auth/domain/app_user.dart';
import 'package:wholeflow_app/features/auth/presentation/auth_screens.dart';
import 'package:wholeflow_app/features/auth/presentation/session_controller.dart';
import 'package:wholeflow_app/features/company/data/company_repository.dart';
import 'package:wholeflow_app/features/company/domain/company.dart';
import 'package:wholeflow_app/features/dashboard/data/dashboard_repository.dart';
import 'package:wholeflow_app/features/dashboard/domain/dashboard_models.dart';
import 'package:wholeflow_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:wholeflow_app/features/home/home_shell.dart';
import 'package:wholeflow_app/features/shop_detail/data/transaction_repository.dart';
import 'package:wholeflow_app/features/shop_detail/presentation/shop_detail_screen.dart';
import 'package:wholeflow_app/features/shops/data/shop_repository.dart';
import 'package:wholeflow_app/features/shops/domain/shop.dart';
import 'package:wholeflow_app/features/shops/presentation/shop_tile.dart';
import 'package:wholeflow_app/features/shops/presentation/shops_screen.dart';
import 'package:wholeflow_app/features/staff/presentation/staff_form_screen.dart';

import 'helpers.dart';

const companyA = Company(id: 'co-a', companyName: 'JMJ Marketing', syncStatus: 'SYNCED');
const companyB = Company(id: 'co-b', companyName: 'JK Tyres', syncStatus: 'SYNCED');

const shops = [
  ShopSummary(id: 's1', name: 'PRINCE TYRES -- RAJAKKAD', area: 'Rajakkad', phone: '9847012345', receivable: Money(12345600)),
  ShopSummary(id: 's2', name: 'KERALA AUTO -- PALA', area: 'Pala', receivable: Money(-500000)),
  ShopSummary(id: 's3', name: 'SETTLED STORES', area: 'Pala'),
];

Future<List<Override>> baseOverrides({
  AppUser user = owner,
  List<Company> companies = const [companyA],
  List<CompanyAccess> access = const [],
  FakeShopRepository? shopRepo,
  FakeDashboardRepository? dashboard,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    currentUserProvider.overrideWithValue(user),
    companyRepositoryProvider.overrideWithValue(
      FakeCompanyRepository(companies: companies, access: access, areas: const ['Pala', 'Rajakkad']),
    ),
    shopRepositoryProvider.overrideWithValue(shopRepo ?? FakeShopRepository(shops: shops)),
    dashboardRepositoryProvider.overrideWithValue(dashboard ?? FakeDashboardRepository()),
  ];
}

void main() {
  group('login', () {
    testWidgets('validates empty fields', (tester) async {
      await pumpScreen(tester, const LoginScreen(), overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();
      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
    });

    testWidgets('shows wrong-password error', (tester) async {
      await pumpScreen(
        tester,
        const LoginScreen(),
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(signInError: const AppFailure(FailureKind.invalidCredentials)),
          ),
        ],
      );
      await tester.enterText(find.byKey(const Key('login-email')), 'owner@example.com');
      await tester.enterText(find.byKey(const Key('login-password')), 'nope');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Wrong email or password.'), findsOneWidget);
    });

    testWidgets('disabled account is signed out with a message', (tester) async {
      final repo = FakeAuthRepository(profile: staffUser.copyWith(isActive: false));
      await pumpScreen(tester, const LoginScreen(), overrides: [authRepositoryProvider.overrideWithValue(repo)]);
      await tester.enterText(find.byKey(const Key('login-email')), 'ravi@example.com');
      await tester.enterText(find.byKey(const Key('login-password')), 'password1');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(find.text(inactiveAccountMessage), findsOneWidget);
      expect(repo.signedIn, isFalse);
    });
  });

  group('shops list', () {
    testWidgets('loading shows skeletons', (tester) async {
      await pumpScreen(tester, const ShopsScreen(), overrides: await baseOverrides(shopRepo: FakeShopRepository(pending: true)));
      await tester.pump();
      await tester.pump();
      expect(find.bySemanticsLabel('Loading'), findsWidgets);
    });

    testWidgets('data rows show balance with side', (tester) async {
      await pumpScreen(tester, const ShopsScreen(), overrides: await baseOverrides());
      await tester.pumpAndSettle();
      expect(find.text('PRINCE TYRES -- RAJAKKAD'), findsOneWidget);
      expect(find.text('₹1,23,456.00 Dr'), findsOneWidget);
      expect(find.text('₹5,000.00 Cr'), findsOneWidget);
      expect(find.descendant(of: find.byType(ShopTile), matching: find.text('Settled')), findsOneWidget);
    });

    testWidgets('empty state offers to clear filters', (tester) async {
      await pumpScreen(tester, const ShopsScreen(), overrides: await baseOverrides(shopRepo: FakeShopRepository()));
      await tester.pumpAndSettle();
      expect(find.text('No shops match'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);
    });

    testWidgets('error state has Retry', (tester) async {
      await pumpScreen(
        tester,
        const ShopsScreen(),
        overrides: await baseOverrides(shopRepo: FakeShopRepository(error: const AppFailure(FailureKind.network))),
      );
      await tester.pumpAndSettle();
      expect(find.text("You're offline"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('balance filter chip changes the query', (tester) async {
      final repo = FakeShopRepository(shops: shops);
      await pumpScreen(tester, const ShopsScreen(), overrides: await baseOverrides(shopRepo: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Owes us'));
      await tester.pumpAndSettle();
      expect(repo.requested.last.balance, BalanceFilter.owes);
    });
  });

  group('shop detail', () {
    const detail = ShopDetail(
      id: 's1',
      companyId: 'co-a',
      name: 'PRINCE TYRES -- RAJAKKAD',
      area: 'Rajakkad',
      phone: '9847012345',
      receivable: Money(12345600),
    );

    Future<List<Override>> overrides(AppUser user, List<CompanyAccess> access) async => [
      ...await baseOverrides(
        user: user,
        access: access,
        shopRepo: FakeShopRepository(detailShop: detail),
      ),
      transactionRepositoryProvider.overrideWithValue(FakeTransactionRepository()),
    ];

    testWidgets('owner sees the Statement tab', (tester) async {
      await pumpScreen(tester, const ShopDetailScreen(shopId: 's1'), overrides: await overrides(owner, const []));
      await tester.pumpAndSettle();
      expect(find.text('Statement'), findsOneWidget);
      expect(find.byTooltip('Call 9847012345'), findsOneWidget);
      expect(find.byTooltip('WhatsApp 9847012345'), findsOneWidget);
    });

    testWidgets('staff without transaction access see no Statement tab', (tester) async {
      await pumpScreen(
        tester,
        const ShopDetailScreen(shopId: 's1'),
        overrides: await overrides(staffUser, const [
          CompanyAccess(userId: 'staff-1', companyId: 'co-a', canViewTransactions: false),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Statement'), findsNothing);
      expect(find.text('Owes you'), findsOneWidget);
    });

    testWidgets('staff with transaction access see the Statement tab', (tester) async {
      await pumpScreen(
        tester,
        const ShopDetailScreen(shopId: 's1'),
        overrides: await overrides(staffUser, const [CompanyAccess(userId: 'staff-1', companyId: 'co-a')]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Statement'), findsOneWidget);
    });
  });

  group('staff form', () {
    testWidgets('requires at least one company', (tester) async {
      await pumpScreen(
        tester,
        const StaffFormScreen(),
        overrides: await baseOverrides(companies: const [companyA, companyB]),
        size: const Size(400, 1400),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('staff-name')), 'Ravi');
      await tester.enterText(find.byKey(const Key('staff-email')), 'ravi@example.com');
      await tester.ensureVisible(find.byKey(const Key('staff-submit')));
      await tester.tap(find.byKey(const Key('staff-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('company-error')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);

      // Ticking a company reveals its per-company settings and clears the error.
      await tester.tap(find.widgetWithText(CheckboxListTile, 'JK Tyres'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('company-error')), findsNothing);
      expect(find.text('All areas'), findsOneWidget);
      expect(find.text('Can view transactions'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('staff-submit')));
      await tester.tap(find.byKey(const Key('staff-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Ravi will see: JK Tyres (all areas)'), findsOneWidget);
    });
  });

  testWidgets('staff with no company see the not-assigned screen', (tester) async {
    await pumpScreen(tester, const NoCompanyView(isOwner: false), overrides: await baseOverrides(user: staffUser));
    await tester.pump();
    expect(find.text("You haven't been assigned to any company yet"), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('shop row survives 200% text scale', (tester) async {
    await pumpScreen(
      tester,
      MediaQuery(
        data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: ListView(
            children: const [
              ListTile(
                title: Text('A VERY LONG SHOP NAME THAT GOES ON AND ON -- RAJAKKAD', maxLines: 2),
                trailing: SizedBox(width: 150, child: BalanceText(Money(1234567890), textAlign: TextAlign.end)),
              ),
            ],
          ),
        ),
      ),
      size: const Size(360, 800),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('dashboard golden', () {
    for (final dark in [false, true]) {
      testWidgets(dark ? 'dark' : 'light', (tester) async {
        await pumpScreen(
          tester,
          const DashboardScreen(),
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          overrides: await baseOverrides(
            dashboard: FakeDashboardRepository(
              summaryRow: const CompanySummary(
                companyId: 'co-a',
                companyName: 'JMJ Marketing',
                shops: 323,
                shopsWithDues: 153,
                totalOutstanding: Money(359524495),
                totalCredit: Money(17649968),
              ),
              state: SyncState(lastSuccessfulSyncAt: DateTime.now().subtract(const Duration(minutes: 4))),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('₹36 L'), findsOneWidget);
        expect(find.text('₹35,95,244.95'), findsOneWidget);
        expect(find.text('Updated 4 min ago'), findsOneWidget);
        await expectLater(find.byType(DashboardScreen), matchesGoldenFile('goldens/dashboard_${dark ? 'dark' : 'light'}.png'));
      });
    }
  });
}
