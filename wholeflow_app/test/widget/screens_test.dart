import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wholeflow_app/core/errors/app_failure.dart';
import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/features/shop_detail/domain/statement.dart';
import 'package:wholeflow_app/core/providers.dart';
import 'package:wholeflow_app/core/theme/app_theme.dart';
import 'package:wholeflow_app/core/widgets/balance_text.dart';
import 'package:wholeflow_app/core/widgets/multi_picker_sheet.dart';
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
import 'package:wholeflow_app/features/sites/data/site_repository.dart';
import 'package:wholeflow_app/features/sites/domain/site.dart';
import 'package:wholeflow_app/features/sites/presentation/site_editor_screen.dart';
import 'package:wholeflow_app/features/sites/presentation/sites_screen.dart';
import 'package:wholeflow_app/features/visits/data/shop_location_repository.dart';
import 'package:wholeflow_app/features/visits/domain/shop_location.dart';
import 'package:wholeflow_app/features/visits/presentation/suggestions_screen.dart';
import 'package:wholeflow_app/features/visits/data/visit_repository.dart';
import 'package:wholeflow_app/features/visits/domain/visit.dart';
import 'package:wholeflow_app/features/visits/presentation/check_in_screen.dart';
import 'package:wholeflow_app/features/visits/presentation/plans_screen.dart';
import 'package:wholeflow_app/features/visits/presentation/staff_visits_screen.dart';
import 'package:wholeflow_app/core/location/location_service.dart';
import 'package:wholeflow_app/features/staff/domain/staff.dart';
import 'package:wholeflow_app/features/staff/presentation/staff_providers.dart';
import 'package:wholeflow_app/features/staff/presentation/staff_form_screen.dart';

import 'helpers.dart';

const companyA = Company(id: 'co-a', companyName: 'JMJ Marketing', syncStatus: 'SYNCED');
const companyB = Company(id: 'co-b', companyName: 'JK Tyres', syncStatus: 'SYNCED');

const shops = [
  ShopSummary(
    id: 's1',
    name: 'PRINCE TYRES -- RAJAKKAD',
    area: 'Rajakkad',
    phone: '9847012345',
    receivable: Money(12345600),
    siteId: 'site-r',
    siteName: 'Rajakkad',
  ),
  ShopSummary(
    id: 's2',
    name: 'KERALA AUTO -- PALA',
    area: 'Pala',
    receivable: Money(-500000),
    siteId: 'site-p',
    siteName: 'Pala',
  ),
  ShopSummary(id: 's3', name: 'SETTLED STORES', area: 'Pala', siteId: 'site-p', siteName: 'Pala'),
];

const sites = [
  Site(id: 'site-p', companyId: 'co-a', name: 'Pala'),
  Site(id: 'site-r', companyId: 'co-a', name: 'Rajakkad'),
  Site(id: 'site-b', companyId: 'co-b', name: 'Kply'),
];

Future<List<Override>> baseOverrides({
  AppUser user = owner,
  List<Company> companies = const [companyA],
  List<CompanyAccess> access = const [],
  FakeShopRepository? shopRepo,
  FakeDashboardRepository? dashboard,
  FakeOverdueRepository? overdueRepo,
  FakeSiteRepository? siteRepo,
  FakeShopLocationRepository? locationRepo,
  FakeVisitRepository? visitRepo,
  LocationReading? location,
  bool devMode = false,
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
    dashboardRepositoryProvider.overrideWithValue(dashboard ?? FakeDashboardRepository(topDues: shops)),
    analyticsRepositoryProvider.overrideWithValue(FakeAnalyticsRepository()),
    overdueRepositoryProvider.overrideWithValue(overdueRepo ?? FakeOverdueRepository()),
    siteRepositoryProvider.overrideWithValue(siteRepo ?? FakeSiteRepository(sitesList: sites)),
    shopLocationRepositoryProvider.overrideWithValue(locationRepo ?? FakeShopLocationRepository()),
    visitRepositoryProvider.overrideWithValue(visitRepo ?? FakeVisitRepository()),
    locationServiceProvider.overrideWithValue(
      FakeLocationService(
        location ?? const LocationReading(latitude: 9.85, longitude: 76.97, accuracyMeters: 10, isMocked: false),
        devMode: devMode,
      ),
    ),
  ];
}

/// As `overdue_shops()` returns it; [withBills] false is staff without transaction access.
OverdueShop overdueShop({bool withBills = true}) => OverdueShop.fromJson({
  'shop_id': 's1',
  'name': 'PRINCE TYRES -- RAJAKKAD',
  'area': 'Rajakkad',
  'site_id': 'site-r',
  'site_name': 'Rajakkad',
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
    const owing = [
      ...shops,
      ShopSummary(
        id: 's4',
        name: 'ROYAL TYRES -- PALA',
        area: 'Pala',
        receivable: Money(200000),
        siteId: 'site-p',
        siteName: 'Pala',
      ),
    ];

    testWidgets('opens on Dues: shops that owe, by site, with the grand total', (tester) async {
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
      expect(find.text('1 shop in 1 site'), findsOneWidget);

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

    testWidgets('owner sees the shop has no location and can set it; staff do not see an empty one', (tester) async {
      await pumpScreen(
        tester,
        const ShopDetailScreen(shopId: 's1'),
        overrides: await overrides(owner, const []),
        size: const Size(400, 1400),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not set. Staff check-ins wait for your approval.'), findsOneWidget);
      expect(find.byKey(const Key('edit-location')), findsOneWidget);
    });

    testWidgets('staff see no location card while the shop has no pin', (tester) async {
      await pumpScreen(
        tester,
        const ShopDetailScreen(shopId: 's1'),
        overrides: await overrides(staffUser, const [CompanyAccess(userId: 'staff-1', companyId: 'co-a')]),
        size: const Size(400, 1400),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shop location'), findsNothing);
    });

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

    testWidgets('share statement: period, summary and ways to send', (tester) async {
      await pumpScreen(
        tester,
        const ShopDetailScreen(shopId: 's1'),
        overrides: [
          ...await baseOverrides(
            user: owner,
            access: const [],
            shopRepo: FakeShopRepository(detailShop: detail),
          ),
          transactionRepositoryProvider.overrideWithValue(
            FakeTransactionRepository([
              ShopTransaction(
                id: 't1',
                transactionDate: DateTime(2020, 1, 5),
                voucherType: 'Sales',
                voucherNumber: '7',
                debit: const Money(12345600),
                amount: const Money(12345600),
              ),
            ]),
          ),
        ],
        size: const Size(400, 1000),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('share-statement')));
      await tester.pumpAndSettle();
      expect(find.text('Share statement'), findsOneWidget);
      expect(find.text('This financial year'), findsOneWidget);
      // The only voucher is years old: this year starts with it brought forward.
      expect(find.textContaining('0 entries · Opening ₹1,23,456.00 Dr'), findsOneWidget);
      await tester.tap(find.text('All transactions'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 entry · Opening ₹0.00'), findsOneWidget);
      expect(find.text('Balance due ₹1,23,456.00 Dr'), findsOneWidget);
      expect(find.byKey(const Key('share-statement-pdf')), findsOneWidget);
      expect(find.byKey(const Key('share-statement-text')), findsOneWidget);
      expect(find.text('Send text on WhatsApp to 9847012345'), findsOneWidget);
    });

    testWidgets('no share button without access to the statement', (tester) async {
      await pumpScreen(
        tester,
        const ShopDetailScreen(shopId: 's1'),
        overrides: await overrides(staffUser, const [
          CompanyAccess(userId: 'staff-1', companyId: 'co-a', canViewTransactions: false),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('share-statement')), findsNothing);
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

  group('sites', () {
    const report = [
      SiteReportRow(
        siteId: 'site-p',
        siteName: 'Pala',
        shops: 2,
        shopsWithDues: 1,
        outstanding: Money(12345600),
        advance: Money.zero,
        sales: Money(7000000),
        returns: Money.zero,
        collections: Money(3000000),
      ),
      SiteReportRow(siteId: null, siteName: null, shops: 1, shopsWithDues: 0, outstanding: Money.zero, advance: Money.zero),
    ];

    testWidgets('lists each site with dues, sales and collections, and shops in no site', (tester) async {
      await pumpScreen(
        tester,
        const SitesScreen(),
        overrides: await baseOverrides(
          siteRepo: FakeSiteRepository(sitesList: sites, reportRows: report),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pala'), findsOneWidget);
      expect(find.text('2 shops'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Outstanding ₹1,23,456\.00')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Sales ₹70,000\.00')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Collected ₹30,000\.00')), findsOneWidget);
      expect(find.text('Shops in no site'), findsOneWidget);
      expect(find.text('New site'), findsOneWidget);
      // Without transaction access the row has no money figures to show.
      expect(find.bySemanticsLabel(RegExp(r'^Sales')), findsOneWidget);
    });

    testWidgets('new site: name required, shops chosen, moves from another site confirmed', (tester) async {
      final repo = FakeSiteRepository(
        sitesList: sites,
        shops: const [
          SiteShop(id: 's1', name: 'PRINCE TYRES -- RAJAKKAD', area: 'Rajakkad', siteId: 'site-r'),
          SiteShop(id: 's9', name: 'NEW SHOP', area: 'Pala'),
        ],
      );
      await pumpRoutedScreen(tester, const SiteEditorScreen(), overrides: await baseOverrides(siteRepo: repo));
      await tester.pumpAndSettle();
      expect(find.textContaining('in Rajakkad', findRichText: true), findsOneWidget);

      await tester.tap(find.byKey(const Key('save-site')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('site-name')), 'Town');
      await tester.tap(find.widgetWithText(CheckboxListTile, 'PRINCE TYRES -- RAJAKKAD'));
      await tester.tap(find.widgetWithText(CheckboxListTile, 'NEW SHOP'));
      await tester.pump();
      expect(find.text('Create site with 2 shops'), findsOneWidget);
      await tester.tap(find.byKey(const Key('save-site')));
      await tester.pumpAndSettle();
      expect(find.text('Move 1 shop?'), findsOneWidget);
      await tester.tap(find.text('Move and save'));
      await tester.pumpAndSettle();
      expect(repo.created, ['Town']);
      expect(repo.saved['site-1'], {'s1', 's9'});
      expect(find.text('at /sites/site-1'), findsOneWidget, reason: 'opens the new site');
    });

    testWidgets('By area adds every shop of the chosen Tally areas', (tester) async {
      final repo = FakeSiteRepository(
        sitesList: sites,
        shops: const [
          SiteShop(id: 'a', name: 'SHOP A', area: 'Pala'),
          SiteShop(id: 'b', name: 'SHOP B', area: 'Pala'),
          SiteShop(id: 'c', name: 'SHOP C', area: 'Rajakkad'),
        ],
      );
      await pumpScreen(tester, const SiteEditorScreen(), overrides: await baseOverrides(siteRepo: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('By area'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(MultiPickerSheet), matching: find.text('Pala')));
      await tester.pump();
      await tester.tap(find.text('Add shops of 1 area'));
      await tester.pumpAndSettle();
      expect(find.text('Create site with 2 shops'), findsOneWidget);
    });
  });

  testWidgets('location suggestions: approve pins the shop and leaves the list', (tester) async {
    final repo = FakeShopLocationRepository(
      suggestions: [
        LocationSuggestion(
          id: 'g1',
          shopId: 's1',
          shopName: 'PRINCE TYRES -- RAJAKKAD',
          staffName: 'Ravi',
          latitude: 9.85,
          longitude: 76.97,
          accuracyM: 12,
          createdAt: DateTime(2026, 10, 5, 10, 30),
        ),
      ],
    );
    await pumpRoutedScreen(tester, const SuggestionsScreen(), overrides: await baseOverrides(locationRepo: repo));
    await tester.pumpAndSettle();
    expect(find.text('PRINCE TYRES -- RAJAKKAD'), findsOneWidget);
    expect(find.textContaining('Ravi'), findsOneWidget);
    expect(find.textContaining('GPS ±12 m'), findsOneWidget);
    await tester.tap(find.text('Approve pin'));
    await tester.pumpAndSettle();
    expect(repo.reviewed, [('g1', true)]);
    expect(find.text('Nothing to review'), findsOneWidget);
  });

  group('visits', () {
    VisitTask task(String id, String shop, VisitState state) => VisitTask(
      taskId: id,
      companyId: 'co-a',
      staffId: 'staff-1',
      staffName: 'Ravi',
      shopId: 's-$id',
      shopName: shop,
      siteName: 'Pala',
      visitDate: DateTime.now(),
      state: state,
    );

    testWidgets('staff Today: progress, shops still to visit first', (tester) async {
      final repo = FakeVisitRepository(
        taskList: [task('1', 'DONE SHOP', VisitState.verified), task('2', 'NEXT SHOP', VisitState.pending)],
      );
      await pumpScreen(
        tester,
        const StaffVisitsScreen(),
        overrides: await baseOverrides(user: staffUser, visitRepo: repo),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 shops checked in'), findsOneWidget);
      expect(tester.getTopLeft(find.text('NEXT SHOP')).dy, lessThan(tester.getTopLeft(find.text('DONE SHOP')).dy));
      expect(find.text('To visit'), findsOneWidget);
      expect(find.text('Checked in'), findsOneWidget);
    });

    testWidgets('check-in: out of range is refused with the distance; in range is accepted', (tester) async {
      final repo = FakeVisitRepository(
        answer: const CheckInResult(result: 'rejected', reason: 'out_of_range', distanceM: 312, radiusM: 100),
      );
      final pins = FakeShopLocationRepository(
        pins: {'s-2': const ShopLocation(shopId: 's-2', latitude: 9.85, longitude: 76.97, radiusM: 100)},
      );
      await pumpRoutedScreen(
        tester,
        CheckInScreen(task: task('2', 'NEXT SHOP', VisitState.pending)),
        overrides: await baseOverrides(user: staffUser, visitRepo: repo, locationRepo: pins),
        size: const Size(400, 1200),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 m from the shop'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Owner away');
      await tester.tap(find.byKey(const Key('check-in')));
      await tester.pumpAndSettle();
      expect(find.text('Check-in refused: 312 m from the shop (allowed 100 m)'), findsOneWidget);
      expect(repo.checkIns.single, ('2', 'Owner away'));

      repo.answer = const CheckInResult(result: 'verified', distanceM: 4, radiusM: 100);
      await tester.tap(find.byKey(const Key('check-in')));
      await tester.pumpAndSettle();
      expect(find.text('Checked in at NEXT SHOP'), findsOneWidget);
    });

    testWidgets('check-in: a small shop radius under the GPS accuracy says to wait for a better fix', (tester) async {
      final pins = FakeShopLocationRepository(
        pins: {'s-2': const ShopLocation(shopId: 's-2', latitude: 9.85, longitude: 76.97, radiusM: 5)},
      );
      await pumpRoutedScreen(
        tester,
        CheckInScreen(task: task('2', 'TINY SHOP', VisitState.pending)),
        overrides: await baseOverrides(user: staffUser, locationRepo: pins),
        size: const Size(400, 1400),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining("rougher than this shop's 5 m limit"), findsOneWidget);
    });

    testWidgets('check-in: Developer options on shows the warning and keeps Check in off', (tester) async {
      final repo = FakeVisitRepository();
      await pumpRoutedScreen(
        tester,
        CheckInScreen(task: task('2', 'NEXT SHOP', VisitState.pending)),
        overrides: await baseOverrides(user: staffUser, visitRepo: repo, devMode: true),
        size: const Size(400, 1400),
      );
      await tester.pumpAndSettle();
      expect(find.text('Check-in disabled'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Check-in is off while Developer options are on'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(find.byKey(const Key('check-in')));
      expect(button.onPressed, isNull);
      expect(repo.checkIns, isEmpty);
    });

    testWidgets('plan editor offers only staff who check in, then their sites', (tester) async {
      final staff = [
        const StaffMember(
          id: 'staff-1',
          role: UserRole.staff,
          name: 'Ravi',
          requiresCheckIn: true,
          companies: [
            CompanyAccess(userId: 'staff-1', companyId: 'co-a', fullCompany: false, siteIds: ['site-p']),
          ],
        ),
        const StaffMember(
          id: 'staff-2',
          role: UserRole.staff,
          name: 'Office Anu',
          companies: [CompanyAccess(userId: 'staff-2', companyId: 'co-a')],
        ),
      ];
      final repo = FakeVisitRepository();
      await pumpRoutedScreen(
        tester,
        const PlanEditorScreen(),
        overrides: [
          ...await baseOverrides(visitRepo: repo),
          staffMembersProvider.overrideWith((ref) async => staff),
        ],
        size: const Size(400, 1200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan-staff')));
      await tester.pumpAndSettle();
      expect(find.text('Office Anu'), findsNothing);
      await tester.tap(find.text('Ravi').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-site-staff-1')));
      await tester.pumpAndSettle();
      expect(find.text('Rajakkad'), findsNothing, reason: 'Ravi has only Pala');
      await tester.tap(find.text('Pala').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-plan')));
      await tester.pumpAndSettle();
      expect(repo.created.single['site'], 'site-p');
      expect(find.text('base page'), findsOneWidget, reason: 'went back after saving');
      expect(repo.created.single['staff'], 'staff-1');
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
      expect(find.text('Full company'), findsOneWidget);
      expect(find.text('Can view transactions'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('staff-submit')));
      await tester.tap(find.byKey(const Key('staff-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Ravi will see: JK Tyres (full company)'), findsOneWidget);
      expect(find.text('No shop check-in.'), findsOneWidget);
    });

    testWidgets('limited to sites: needs a site, then names it; check-in can be turned on', (tester) async {
      await pumpScreen(
        tester,
        const StaffFormScreen(),
        overrides: await baseOverrides(companies: const [companyA, companyB]),
        size: const Size(400, 1600),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('staff-name')), 'Ravi');
      await tester.enterText(find.byKey(const Key('staff-email')), 'ravi@example.com');
      await tester.tap(find.byKey(const Key('staff-check-in')));
      await tester.tap(find.widgetWithText(CheckboxListTile, 'JMJ Marketing'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Full company'));
      await tester.pumpAndSettle();
      expect(find.text('Choose sites'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('staff-submit')));
      await tester.tap(find.byKey(const Key('staff-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sites-error')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);

      await tester.ensureVisible(find.text('Choose sites'));
      await tester.tap(find.text('Choose sites'));
      await tester.pumpAndSettle();
      // Only JMJ's sites are offered.
      expect(find.widgetWithText(CheckboxListTile, 'Kply'), findsNothing);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Pala'));
      await tester.pump();
      await tester.tap(find.text('Apply (1)'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sites-error')), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('staff-submit')));
      await tester.tap(find.byKey(const Key('staff-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Ravi will see: JMJ Marketing (Pala)'), findsOneWidget);
      expect(find.text('They must check in at shops on planned visit days.'), findsOneWidget);
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

    testWidgets('sort: one list, most overdue first, rows name their site', (tester) async {
      final big = OverdueShop.fromJson({
        'shop_id': 's2',
        'name': 'ROYAL TYRES -- PALA',
        'area': 'Pala',
        'site_id': 'site-p',
        'site_name': 'Pala',
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
      // By site: Pala before Rajakkad, under site headers.
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
              topDues: shops,
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
