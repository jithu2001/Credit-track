// Renders real app screens with invented data for the product website
// (website/img). Skipped in the normal test run; to regenerate:
//
//   WF_SCREENSHOTS=1 flutter test test/marketing --update-goldens
//
// Output: test/marketing/out/*.png at 1080×2400 (360×800 logical, ×3).
// Every name and amount here is invented: no real business, phone or key.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wholeflow_app/core/location/location_service.dart';
import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/core/providers.dart';
import 'package:wholeflow_app/core/theme/app_theme.dart';
import 'package:wholeflow_app/features/analytics/data/analytics_repository.dart';
import 'package:wholeflow_app/features/analytics/domain/payment_analysis.dart';
import 'package:wholeflow_app/features/auth/domain/app_user.dart';
import 'package:wholeflow_app/features/auth/presentation/session_controller.dart';
import 'package:wholeflow_app/features/company/data/company_repository.dart';
import 'package:wholeflow_app/features/company/domain/company.dart';
import 'package:wholeflow_app/features/dashboard/data/dashboard_repository.dart';
import 'package:wholeflow_app/features/dashboard/domain/dashboard_models.dart';
import 'package:wholeflow_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:wholeflow_app/features/home/home_shell.dart';
import 'package:wholeflow_app/features/home/staff_home_shell.dart';
import 'package:wholeflow_app/features/inventory/data/inventory_repository.dart';
import 'package:wholeflow_app/features/inventory/domain/stock_item.dart';
import 'package:wholeflow_app/features/outstanding/data/overdue_repository.dart';
import 'package:wholeflow_app/features/outstanding/domain/overdue_report.dart';
import 'package:wholeflow_app/features/purchases/data/purchase_repository.dart';
import 'package:wholeflow_app/features/purchases/domain/purchase.dart';
import 'package:wholeflow_app/features/shop_detail/data/transaction_repository.dart';
import 'package:wholeflow_app/features/shop_detail/domain/statement.dart';
import 'package:wholeflow_app/features/shop_detail/presentation/shop_detail_screen.dart';
import 'package:wholeflow_app/features/shops/data/shop_repository.dart';
import 'package:wholeflow_app/features/shops/domain/shop.dart';
import 'package:wholeflow_app/features/shops/presentation/shops_screen.dart';
import 'package:wholeflow_app/features/sites/data/site_repository.dart';
import 'package:wholeflow_app/features/sites/domain/site.dart';
import 'package:wholeflow_app/features/sites/presentation/sites_screen.dart';
import 'package:wholeflow_app/features/stock/stock_screen.dart';
import 'package:wholeflow_app/features/suppliers/data/supplier_repository.dart';
import 'package:wholeflow_app/features/suppliers/domain/supplier.dart';
import 'package:wholeflow_app/features/visits/data/shop_location_repository.dart';
import 'package:wholeflow_app/features/visits/data/visit_repository.dart';
import 'package:wholeflow_app/features/visits/domain/visit.dart';
import 'package:wholeflow_app/features/visits/presentation/staff_visits_screen.dart';

import '../widget/helpers.dart';

final _skip = Platform.environment['WF_SCREENSHOTS'] == null;

const _company = Company(id: 'co', companyName: 'Periyar Traders (FY 2026-27)', syncStatus: 'SYNCED');
const _staff = AppUser(id: 'staff-1', businessId: 'biz', role: UserRole.staff, name: 'Anand', requiresCheckIn: true);

ShopSummary _shop(String id, String name, String site, int rupees, {int paise = 0}) => ShopSummary(
  id: id,
  name: name,
  area: site,
  receivable: Money(rupees * 100 + paise),
  siteId: 'site-${site.toLowerCase()}',
  siteName: site,
);

final _shops = [
  _shop('s1', 'MALABAR AUTO SPARES -- KUMILY', 'Kumily', 184850),
  _shop('s2', 'HIGHRANGE TYRE HOUSE -- KATTAPPANA', 'Kattappana', 152900),
  _shop('s3', 'GREENVALLEY MOTORS -- NEDUMKANDAM', 'Kattappana', 96420, paise: 50),
  _shop('s4', 'CARDAMOM HILLS AGENCIES -- VANDANMEDU', 'Kumily', 74880),
  _shop('s5', 'RIVERSIDE LUBES -- ADIMALI', 'Adimali', 61200),
  _shop('s6', 'TEAVALLEY AUTO CENTRE -- THODUPUZHA', 'Thodupuzha', 48315),
  _shop('s7', 'MISTY PEAK MOTOR WORKS -- MUNNAR', 'Adimali', 33760),
  _shop('s8', 'KAILAS TYRES -- KUMILY', 'Kumily', -12500),
];

const _sites = [
  Site(id: 'site-kumily', companyId: 'co', name: 'Kumily'),
  Site(id: 'site-kattappana', companyId: 'co', name: 'Kattappana'),
  Site(id: 'site-adimali', companyId: 'co', name: 'Adimali'),
  Site(id: 'site-thodupuzha', companyId: 'co', name: 'Thodupuzha'),
];

final _today = DateTime.now();
DateTime _ago(int days) => DateTime(_today.year, _today.month, _today.day).subtract(Duration(days: days));
String _d(int days) => _ago(days).toIso8601String().substring(0, 10);

OverdueShop _overdue(
  String id,
  String name,
  String site,
  int receivable,
  int overdue,
  int days,
  List<(int, String, int)> bills,
) => OverdueShop.fromJson({
  'shop_id': id,
  'name': name,
  'area': site,
  'site_id': 'site-${site.toLowerCase()}',
  'site_name': site,
  'phone': null,
  'receivable': receivable,
  'overdue': overdue,
  'max_days_overdue': days,
  'overdue_bills': bills.length,
  'bills_visible': true,
  'bills': [
    for (final (age, voucher, amount) in bills)
      {'date': _d(age), 'voucher': voucher, 'amount': amount, 'remaining': amount, 'days_overdue': age - 30},
  ],
});

final _overdueShops = [
  _overdue('s2', 'HIGHRANGE TYRE HOUSE -- KATTAPPANA', 'Kattappana', 152900, 88400, 52, [
    (82, 'Sales · PT/1183', 51200),
    (64, 'Sales · PT/1246', 37200),
  ]),
  _overdue('s1', 'MALABAR AUTO SPARES -- KUMILY', 'Kumily', 184850, 62750, 37, [(67, 'Sales · PT/1209', 62750)]),
  _overdue('s5', 'RIVERSIDE LUBES -- ADIMALI', 'Adimali', 61200, 24900, 19, [(49, 'Sales · PT/1301', 24900)]),
  _overdue('s7', 'MISTY PEAK MOTOR WORKS -- MUNNAR', 'Adimali', 33760, 18210, 8, [(38, 'Sales · PT/1352', 18210)]),
];

/// Unpaid bills older than 30 days for the same shops as the Overdue view.
class _Analytics implements AnalyticsRepository {
  @override
  Future<AnalyticsData> load(String companyId) async {
    PaymentTxn sale(String shop, int daysAgo, int rupees, String no) => PaymentTxn(
      shopId: shop,
      date: _ago(daysAgo),
      category: TxnCategory.sales,
      debit: Money(rupees * 100),
      credit: Money.zero,
      voucher: 'Sales · $no',
    );
    return AnalyticsData(
      booksFrom: _ago(365),
      shops: [
        for (final s in _shops.take(7))
          ShopOpening(id: s.id, name: s.name, siteName: s.siteName, opening: Money.zero, receivable: s.receivable),
      ],
      txns: [
        sale('s2', 82, 51200, 'PT/1183'),
        sale('s2', 64, 37200, 'PT/1246'),
        sale('s2', 12, 64500, 'PT/1440'),
        sale('s1', 67, 62750, 'PT/1209'),
        sale('s1', 20, 121600, 'PT/1411'),
        sale('s5', 49, 24900, 'PT/1301'),
        sale('s5', 9, 36300, 'PT/1458'),
        sale('s7', 38, 18210, 'PT/1352'),
        sale('s7', 6, 15550, 'PT/1466'),
        sale('s3', 15, 96420, 'PT/1425'),
        sale('s4', 11, 74880, 'PT/1437'),
        sale('s6', 8, 48315, 'PT/1461'),
      ],
    );
  }
}

class _Dashboard implements DashboardRepository {
  @override
  Future<CompanySummary?> summary(String companyId) async => const CompanySummary(
    companyId: 'co',
    companyName: 'Periyar Traders (FY 2026-27)',
    shops: 214,
    shopsWithDues: 96,
    totalOutstanding: Money(248641250),
    totalCredit: Money(11230000),
  );
  @override
  Future<SyncState?> syncState(String companyId) async =>
      SyncState(lastSuccessfulSyncAt: DateTime.now().subtract(const Duration(minutes: 3)));
  @override
  Future<MonthSales> monthSales(String companyId, DateTime now) async =>
      MonthSales(month: DateTime(now.year, now.month), amount: const Money(684215000), bills: 143);
}

ShopTransaction _txn(String id, int daysAgo, TxnCategory cat, String type, String no, {int debit = 0, int credit = 0}) =>
    ShopTransaction(
      id: id,
      transactionDate: _ago(daysAgo),
      voucherType: type,
      voucherNumber: no,
      category: cat,
      debit: Money(debit * 100),
      credit: Money(credit * 100),
      amount: Money((debit - credit) * 100),
    );

final _statement = [
  _txn('t1', 74, TxnCategory.sales, 'Sales', 'PT/1188', debit: 96400),
  _txn('t2', 67, TxnCategory.sales, 'Sales', 'PT/1209', debit: 62750),
  _txn('t3', 52, TxnCategory.receipts, 'Receipt', 'RC/412', credit: 80000),
  _txn('t4', 40, TxnCategory.returns, 'Credit Note', 'CN/57', credit: 6200),
  _txn('t5', 26, TxnCategory.sales, 'Sales', 'PT/1388', debit: 71900),
  _txn('t6', 12, TxnCategory.receipts, 'Receipt', 'RC/455', credit: 30000),
  _txn('t7', 4, TxnCategory.sales, 'Sales', 'PT/1452', debit: 70000),
];

class _Inventory implements InventoryRepository {
  @override
  Future<List<StockItem>> items(String companyId, {required bool withCosts}) async => [
    StockItem(
      id: 'i1',
      name: 'TYRE 145/80 R12 TL',
      group: 'Tyres',
      unit: 'Nos',
      closingQty: 1250,
      closingValue: withCosts ? const Money(287500000) : null,
    ),
    StockItem(
      id: 'i2',
      name: 'TYRE 90/100-10 TL',
      group: 'Tyres',
      unit: 'Nos',
      closingQty: 642,
      closingValue: withCosts ? const Money(96300000) : null,
    ),
    StockItem(
      id: 'i3',
      name: 'ENGINE OIL 20W40 1 L',
      group: 'Lubricants',
      unit: 'Ltr',
      closingQty: 388,
      closingValue: withCosts ? const Money(15132000) : null,
    ),
    StockItem(
      id: 'i4',
      name: 'TUBE 3.00-17',
      group: 'Tubes',
      unit: 'Nos',
      closingQty: 14,
      reorderLevel: 50,
      closingValue: withCosts ? const Money(2940000) : null,
    ),
    StockItem(
      id: 'i5',
      name: 'BRAKE SHOE SET (2W)',
      group: 'Spares',
      unit: 'Set',
      closingQty: 9,
      reorderLevel: 40,
      closingValue: withCosts ? const Money(1782000) : null,
    ),
    const StockItem(id: 'i6', name: 'CHAIN SPROCKET KIT', group: 'Spares', unit: 'Kit', closingQty: 0),
  ];
  @override
  Future<StockItem> item(String itemId, {required bool withCosts}) async => throw UnimplementedError();
  @override
  Future<List<ItemPurchase>> purchasesOf(String itemId, {int limit = 20}) async => const [];
  @override
  Future<Map<String, double>> minimums(String companyId) async => const {};
  @override
  Future<void> setMinimum(String companyId, Iterable<String> itemIds, double? min) async {}
}

class _Purchases implements PurchaseRepository {
  @override
  Future<List<PurchaseSummary>> page(PurchaseQuery query, int pageIndex) async => const [];
  @override
  Future<PurchaseDetail> detail(String purchaseId) async => throw UnimplementedError();
  @override
  Future<List<MonthPurchases>> monthTotals(String companyId, DateTime from, {String? supplierId}) async => const [];
}

class _Suppliers implements SupplierRepository {
  @override
  Future<List<Supplier>> all(String companyId) async => const [];
  @override
  Future<Supplier> detail(String supplierId) async => throw UnimplementedError();
}

VisitTask _task(String id, String shop, String site, VisitState state) => VisitTask(
  taskId: id,
  companyId: 'co',
  staffId: 'staff-1',
  staffName: 'Anand',
  shopId: 's-$id',
  shopName: shop,
  siteName: site,
  visitDate: DateTime.now(),
  state: state,
);

Future<List<Override>> _overrides({AppUser user = owner}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    currentUserProvider.overrideWithValue(user),
    companyRepositoryProvider.overrideWithValue(
      FakeCompanyRepository(
        companies: const [_company],
        access: const [CompanyAccess(userId: 'staff-1', companyId: 'co', canViewTransactions: true)],
      ),
    ),
    shopRepositoryProvider.overrideWithValue(
      FakeShopRepository(
        shops: _shops,
        detailShop: const ShopDetail(
          id: 's1',
          companyId: 'co',
          name: 'MALABAR AUTO SPARES -- KUMILY',
          area: 'Kumily',
          receivable: Money(18485000),
        ),
      ),
    ),
    dashboardRepositoryProvider.overrideWithValue(_Dashboard()),
    analyticsRepositoryProvider.overrideWithValue(_Analytics()),
    overdueRepositoryProvider.overrideWithValue(FakeOverdueRepository(_overdueShops)),
    siteRepositoryProvider.overrideWithValue(
      FakeSiteRepository(
        sitesList: _sites,
        reportRows: const [
          SiteReportRow(
            siteId: 'site-kumily',
            siteName: 'Kumily',
            shops: 58,
            shopsWithDues: 31,
            outstanding: Money(84213000),
            advance: Money(1250000),
            sales: Money(192840000),
            returns: Money(2105000),
            collections: Money(161520000),
          ),
          SiteReportRow(
            siteId: 'site-kattappana',
            siteName: 'Kattappana',
            shops: 64,
            shopsWithDues: 29,
            outstanding: Money(76054250),
            advance: Money.zero,
            sales: Money(214330000),
            returns: Money(980000),
            collections: Money(198410000),
          ),
          SiteReportRow(
            siteId: 'site-adimali',
            siteName: 'Adimali',
            shops: 47,
            shopsWithDues: 22,
            outstanding: Money(52896000),
            advance: Money(980000),
            sales: Money(143600000),
            returns: Money.zero,
            collections: Money(127250000),
          ),
          SiteReportRow(
            siteId: 'site-thodupuzha',
            siteName: 'Thodupuzha',
            shops: 45,
            shopsWithDues: 14,
            outstanding: Money(35478000),
            advance: Money.zero,
            sales: Money(133445000),
            returns: Money(1450000),
            collections: Money(121960000),
          ),
        ],
      ),
    ),
    shopLocationRepositoryProvider.overrideWithValue(FakeShopLocationRepository()),
    visitRepositoryProvider.overrideWithValue(
      FakeVisitRepository(
        taskList: [
          _task('1', 'MALABAR AUTO SPARES -- KUMILY', 'Kumily', VisitState.verified),
          _task('2', 'CARDAMOM HILLS AGENCIES -- VANDANMEDU', 'Kumily', VisitState.verified),
          _task('3', 'KAILAS TYRES -- KUMILY', 'Kumily', VisitState.verified),
          _task('4', 'THEKKADY MOTOR STORES -- KUMILY', 'Kumily', VisitState.pending),
          _task('5', 'SPICE ROUTE AUTOMOBILES -- KUMILY', 'Kumily', VisitState.pending),
          _task('6', 'HILLVIEW TYRE POINT -- CHELIMADA', 'Kumily', VisitState.pending),
        ],
      ),
    ),
    locationServiceProvider.overrideWithValue(
      const FakeLocationService(LocationReading(latitude: 9.60, longitude: 77.16, accuracyMeters: 6, isMocked: false)),
    ),
    transactionRepositoryProvider.overrideWithValue(FakeTransactionRepository(_statement)),
    inventoryRepositoryProvider.overrideWithValue(_Inventory()),
    purchaseRepositoryProvider.overrideWithValue(_Purchases()),
    supplierRepositoryProvider.overrideWithValue(_Suppliers()),
  ];
}

Future<void> _loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<ByteData> f(String name) async => ByteData.view((await File('$dir/$name').readAsBytes()).buffer);
  final roboto = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold', 'Light']) {
    roboto.addFont(f('Roboto-$w.ttf'));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(f('MaterialIcons-Regular.otf'))).load();
}

/// [screen] in a phone-sized frame with the app's real bottom navigation.
Widget _phone(Widget screen, List<NavItem> items, int selected) => Scaffold(
  body: screen,
  bottomNavigationBar: NavigationBar(
    selectedIndex: selected,
    destinations: [
      for (final i in items) NavigationDestination(icon: Icon(i.icon), selectedIcon: Icon(i.selectedIcon), label: i.label),
    ],
  ),
);

Future<void> _shot(
  WidgetTester tester,
  String name,
  Widget screen, {
  AppUser user = owner,
  int nav = 0,
  bool dark = false,
  Future<void> Function()? then,
}) async {
  debugDisableShadows = false; // real elevation shadows in the picture
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(1080, 2400);
  addTearDown(tester.view.reset);
  final items = user.isOwner ? navItemsFor(UserRole.owner) : staffNavItemsFor(checksIn: true);
  await tester.pumpWidget(
    ProviderScope(
      overrides: await _overrides(user: user),
      retry: (_, _) => null,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: RepaintBoundary(key: const Key('shot'), child: _phone(screen, items, nav)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (then != null) {
    await then();
    await tester.pumpAndSettle();
  }
  await expectLater(find.byKey(const Key('shot')), matchesGoldenFile('out/$name.png'));
  debugDisableShadows = true; // the test framework checks it is back to its default
}

void main() {
  setUpAll(() async {
    if (_skip) return;
    await _loadFonts();
  });

  group('marketing screenshots', skip: _skip, () {
    testWidgets('owner dashboard', (t) => _shot(t, 'owner-dashboard', const DashboardScreen()));
    testWidgets('owner dashboard dark', (t) => _shot(t, 'owner-dashboard-dark', const DashboardScreen(), dark: true));
    testWidgets('shops dues', (t) => _shot(t, 'shops-dues', const ShopsScreen(), nav: 1));
    testWidgets(
      'shops overdue',
      (t) => _shot(
        t,
        'shops-overdue',
        const ShopsScreen(),
        nav: 1,
        then: () async {
          await t.tap(find.text('Overdue'));
        },
      ),
    );
    testWidgets(
      'shop statement',
      (t) => _shot(
        t,
        'shop-statement',
        const ShopDetailScreen(shopId: 's1'),
        nav: 1,
        then: () async {
          final statement = find.text('Statement');
          if (statement.evaluate().isNotEmpty) await t.tap(statement.first);
        },
      ),
    );
    testWidgets('sites', (t) => _shot(t, 'sites', const SitesScreen(), nav: 2));
    testWidgets('stock', (t) => _shot(t, 'stock', const StockScreen(), nav: 3));
    testWidgets('staff visits', (t) => _shot(t, 'staff-visits', const StaffVisitsScreen(), user: _staff, nav: 2));
  });
}
