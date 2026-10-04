import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wholeflow_app/core/errors/app_failure.dart';
import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/core/providers.dart';
import 'package:wholeflow_app/core/theme/app_theme.dart';
import 'package:wholeflow_app/core/widgets/balance_text.dart';
import 'package:wholeflow_app/features/analytics/data/analytics_repository.dart';
import 'package:wholeflow_app/features/analytics/presentation/analytics_screen.dart';
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
import 'package:wholeflow_app/features/outstanding/data/overdue_repository.dart';
import 'package:wholeflow_app/features/outstanding/domain/overdue_report.dart';
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
  FakeOverdueRepository? overdueRepo,
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
    analyticsRepositoryProvider.overrideWithValue(FakeAnalyticsRepository()),
    overdueRepositoryProvider.overrideWithValue(overdueRepo ?? FakeOverdueRepository()),
  ];
}

/// As `overdue_shops()` returns it; [withBills] false is staff without transaction access.
OverdueShop overdueShop({bool withBills = true}) => OverdueShop.fromJson({
  'shop_id': 's1',
  'name': 'PRINCE TYRES -- RAJAKKAD',
  'area': 'Rajakkad',
  'phone': null,
  'receivable': 6000,
  'overdue': 3000,
  'max_days_overdue': 20,
  'overdue_bills': 1,
  'bills_visible': withBills,
  'bills': withBills
      ? [
          {'date': '2026-08-10', 'voucher': 'Sales · S1', 'amount': 5000, 'remaining': 3000, 'days_overdue': 20},
        ]
      : null,
});

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
    Future<void> openAllShops(WidgetTester tester) async {
      await tester.pump();
      await tester.tap(find.text('All shops'));
      await tester.pumpAndSettle();
    }

    testWidgets('loading shows skeletons', (tester) async {
      await pumpScreen(tester, const ShopsScreen(), overrides: await baseOverrides(shopRepo: FakeShopRepository(pending: true)));
      await tester.pump();
      await tester.tap(find.text('All shops'));
      await tester.pump();
      await tester.pump();
      expect(find.bySemanticsLabel('Loading'), findsWidgets);
    });

    testWidgets('data rows show balance with side', (tester) async {
      await pumpScreen(tester, const ShopsScreen(), overrides: await baseOverrides());
      await openAllShops(tester);
      expect(find.text('PRINCE TYRES -- RAJAKKAD'), findsOneWidget);
      expect(find.text('₹1,23,456.00 Dr'), findsOneWidget);
      expect(find.text('₹5,000.00 Cr'), findsOneWidget);
      expect(find.descendant(of: find.byType(ShopTile), matching: find.text('Settled')), findsOneWidget);
    });

    testWidgets('empty state offers to clear filters', (tester) async {
      await pumpScreen(tester, const ShopsScreen(), overrides: await baseOverrides(shopRepo: FakeShopRepository()));
      await openAllShops(tester);
      expect(find.text('No shops match'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);
    });

    testWidgets('error state has Retry', (tester) async {
      await pumpScreen(
        tester,
        const ShopsScreen(),
        overrides: await baseOverrides(shopRepo: FakeShopRepository(error: const AppFailure(FailureKind.network))),
      );
      await openAllShops(tester);
      expect(find.text("You're offline"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('balance filter chip changes the query', (tester) async {
      final repo = FakeShopRepository(shops: shops);
      await pumpScreen(tester, const ShopsScreen(), overrides: await baseOverrides(shopRepo: repo));
      await openAllShops(tester);
      expect(find.widgetWithText(FilterChip, 'Owes us'), findsNothing, reason: 'the Dues view replaces it');
      await tester.tap(find.widgetWithText(FilterChip, 'In credit'));
      await tester.pumpAndSettle();
      expect(repo.requested.last.balance, BalanceFilter.credit);
    });
  });

  group('shops dues', () {
    const owing = [...shops, ShopSummary(id: 's4', name: 'ROYAL TYRES -- PALA', area: 'Pala', receivable: Money(200000))];

    testWidgets('opens on Dues: shops that owe, by area, with the grand total', (tester) async {
      await pumpScreen(
        tester,
        const ShopsScreen(),
        overrides: await baseOverrides(shopRepo: FakeShopRepository(shops: owing)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Grand total'), findsOneWidget);
      expect(find.text('₹1,25,456.00'), findsOneWidget);
      expect(find.text('PRINCE TYRES -- RAJAKKAD'), findsOneWidget);
      expect(find.text('ROYAL TYRES -- PALA'), findsOneWidget);
      expect(find.text('KERALA AUTO -- PALA'), findsNothing);
      expect(find.byTooltip('Share report'), findsOneWidget);
      expect(find.byTooltip('Sort'), findsNothing);
    });

    testWidgets('search narrows the dues and recomputes the total', (tester) async {
      await pumpScreen(
        tester,
        const ShopsScreen(),
        overrides: await baseOverrides(shopRepo: FakeShopRepository(shops: owing)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(SearchBar), 'pala');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('ROYAL TYRES -- PALA'), findsOneWidget);
      expect(find.text('PRINCE TYRES -- RAJAKKAD'), findsNothing);
      expect(find.text('1 shop in 1 area'), findsOneWidget);

      await tester.enterText(find.byType(SearchBar), 'nobody');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('No shops match'), findsOneWidget);
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
      expect(find.text('Payments'), findsOneWidget);
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
      expect(find.text('Payments'), findsNothing);
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

  group('analytics', () {
    testWidgets('explains overdue, trend and habits in plain words, and reacts to the period', (tester) async {
      await pumpScreen(tester, const PaymentInsightsScreen(), overrides: await baseOverrides(), size: const Size(900, 2000));
      await tester.pumpAndSettle();
      // 30 days: the ₹10,000 bill from 50 days ago is past the limit.
      expect(find.text('Overdue now'), findsOneWidget);
      expect(find.text('1 shop with bills older than 30 days'), findsOneWidget);
      // A month ago that bill was only 20 days old.
      expect(find.text('₹10,000.00 more than a month ago — getting worse'), findsOneWidget);
      expect(find.text('See who to call'), findsOneWidget);
      // Shop 2 paid its bill 10 days after it: on time; shop 1 never paid.
      expect(find.text('Shops usually pay 10 days after the bill.'), findsOneWidget);
      expect(find.text('Usually pays 10 days after the bill'), findsOneWidget);
      expect(find.text('Has not paid any bill yet'), findsOneWidget);
      expect(find.text('Pays on time'), findsOneWidget);
      expect(find.text('No payments yet'), findsOneWidget);

      await tester.tap(find.text('Pay on time (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Has not paid any bill yet'), findsNothing);

      // 60 days: nothing is past the limit any more; the data is not fetched again.
      await tester.tap(find.widgetWithText(ChoiceChip, '60 days'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing'), findsOneWidget);
      expect(find.text('No bill is older than 60 days'), findsOneWidget);
      expect(find.text('See who to call'), findsNothing);
    });

    testWidgets('dashboard shows the overdue card to owners only', (tester) async {
      await pumpScreen(tester, const DashboardScreen(), overrides: await baseOverrides());
      await tester.pumpAndSettle();
      expect(find.text('₹10,000.00 overdue'), findsOneWidget);
    });

    testWidgets('staff dashboard has no overdue card', (tester) async {
      await pumpScreen(tester, const DashboardScreen(), overrides: await baseOverrides(user: staffUser));
      await tester.pumpAndSettle();
      expect(find.textContaining('overdue'), findsNothing);
      // Staff without transaction access for the company don't get the sales tile.
      expect(find.text('Sales this month'), findsNothing);
    });
  });

  group('shops overdue', () {
    Future<void> openOverdue(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overdue'));
      await tester.pumpAndSettle();
    }

    testWidgets('owner sees amount, days and the bills, and the period re-queries', (tester) async {
      final repo = FakeOverdueRepository([overdueShop()]);
      await pumpScreen(
        tester,
        const ShopsScreen(),
        overrides: await baseOverrides(overdueRepo: repo),
        size: const Size(900, 1600),
      );
      await openOverdue(tester);

      expect(find.text('Past 30 days'), findsOneWidget);
      expect(find.text('₹3,000.00'), findsWidgets);
      expect(find.text('of ₹6,000.00'), findsOneWidget);
      expect(find.text('20 days past limit · 1 bill'), findsOneWidget);
      expect(find.text('Sales · S1'), findsNothing);

      await tester.tap(find.text('PRINCE TYRES -- RAJAKKAD'));
      await tester.pumpAndSettle();
      expect(find.text('Sales · S1'), findsOneWidget);
      expect(find.text('10 Aug 2026 · bill ₹5,000.00, part paid'), findsOneWidget);
      expect(find.text('Open shop'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, '60 days'));
      await tester.pumpAndSettle();
      expect(repo.requestedDays, [30, 60]);
    });

    testWidgets('staff without transaction access get amounts but no bills', (tester) async {
      await pumpScreen(
        tester,
        const ShopsScreen(),
        overrides: await baseOverrides(user: staffUser, overdueRepo: FakeOverdueRepository([overdueShop(withBills: false)])),
      );
      await openOverdue(tester);
      expect(find.text('₹3,000.00'), findsWidgets);
      expect(find.text('20 days past limit · 1 bill'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
      expect(find.textContaining('Sales · S1'), findsNothing);
    });

    testWidgets('sort: one list, most overdue first, rows name their area', (tester) async {
      final big = OverdueShop.fromJson({
        'shop_id': 's2',
        'name': 'ROYAL TYRES -- PALA',
        'area': 'Pala',
        'receivable': 9000,
        'overdue': 9000,
        'max_days_overdue': 5,
        'overdue_bills': 1,
        'bills_visible': false,
      });
      await pumpScreen(
        tester,
        const ShopsScreen(),
        overrides: await baseOverrides(overdueRepo: FakeOverdueRepository([overdueShop(), big])),
        size: const Size(900, 1600),
      );
      await openOverdue(tester);
      // By area: Pala before Rajakkad, under area headers.
      expect(find.text('Pala (1)'), findsOneWidget);

      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Most days late first'));
      await tester.pumpAndSettle();
      expect(find.text('Pala (1)'), findsNothing);
      final prince = find.text('PRINCE TYRES -- RAJAKKAD'), royal = find.text('ROYAL TYRES -- PALA');
      expect(tester.getTopLeft(prince).dy, lessThan(tester.getTopLeft(royal).dy));
      expect(find.text('Rajakkad · 20 days past limit · 1 bill'), findsOneWidget);

      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Most overdue first'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(royal).dy, lessThan(tester.getTopLeft(prince).dy));
    });

    testWidgets('empty state names the period', (tester) async {
      await pumpScreen(tester, const ShopsScreen(), overrides: await baseOverrides());
      await openOverdue(tester);
      expect(find.text('No shop is past the limit'), findsOneWidget);
      expect(find.text('Every unpaid bill is within 30 days.'), findsOneWidget);
    });
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
        expect(find.text('In credit'), findsNothing);
        expect(find.text('Sales this month'), findsOneWidget);
        expect(find.text('₹45.7 K'), findsOneWidget);
        expect(find.text('Updated 4 min ago'), findsOneWidget);
        await expectLater(find.byType(DashboardScreen), matchesGoldenFile('goldens/dashboard_${dark ? 'dark' : 'light'}.png'));
      });
    }
  });
}
