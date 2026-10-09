// Renders real app screens with invented data for the product website
// (website/img). Skipped in the normal test run; to regenerate:
//
//   WF_SCREENSHOTS=1 flutter test test/marketing
//
// Output: test/marketing/out/*.png at 1080×2400 (360×800 logical, captured at ×3).
//
// Google Play phone screenshots (9:16, 1080×1920, captured at ×3):
//
//   WF_SCREENSHOTS=play flutter test test/marketing
//
// Output: test/marketing/out/play/*.png (owner-* for WholeFlow Owner,
// staff-* for WholeFlow Staff).
// Every name and amount here is invented: no real business, phone or key.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

import '../stock_like_server.dart';
import '../widget/helpers.dart';

final _skip = Platform.environment['WF_SCREENSHOTS'] == null;

/// Play Store mode: 9:16 screens written at full resolution.
final _play = Platform.environment['WF_SCREENSHOTS'] == 'play';

const _company = Company(id: 'co', companyName: 'Sunrise Distributors (FY 2026-27)', syncStatus: 'SYNCED');
const _staff = AppUser(id: 'staff-1', businessId: 'biz', role: UserRole.staff, name: 'Sam', requiresCheckIn: true);

ShopSummary _shop(String id, String name, String site, int rupees, {int paise = 0}) => ShopSummary(
  id: id,
  name: name,
  area: site,
  receivable: Money(rupees * 100 + paise),
  siteId: 'site-${site.toLowerCase()}',
  siteName: site,
);

final _shops = [
  _shop('s1', 'BLUEWAVE AUTO SPARES -- RIVERBEND', 'Riverbend', 184850),
  _shop('s2', 'NORTHSTAR TYRE HOUSE -- HILLVIEW', 'Hillview', 152900),
  _shop('s3', 'EVERGREEN MOTORS -- MAPLE JUNCTION', 'Hillview', 96420, paise: 50),
  _shop('s4', 'BRIGHT STAR AGENCIES -- SILVER OAK', 'Riverbend', 74880),
  _shop('s5', 'COMET LUBES -- LAKESIDE', 'Lakeside', 61200),
  _shop('s6', 'ZENITH AUTO CENTRE -- GREENFIELD', 'Greenfield', 48315),
  _shop('s7', 'ORBIT MOTOR WORKS -- CORAL BAY', 'Lakeside', 33760),
  _shop('s8', 'NOVA TYRES -- RIVERBEND', 'Riverbend', -12500),
];

const _sites = [
  Site(id: 'site-riverbend', companyId: 'co', name: 'Riverbend'),
  Site(id: 'site-hillview', companyId: 'co', name: 'Hillview'),
  Site(id: 'site-lakeside', companyId: 'co', name: 'Lakeside'),
  Site(id: 'site-greenfield', companyId: 'co', name: 'Greenfield'),
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
  _overdue('s2', 'NORTHSTAR TYRE HOUSE -- HILLVIEW', 'Hillview', 152900, 88400, 52, [
    (82, 'Sales · PT/1183', 51200),
    (64, 'Sales · PT/1246', 37200),
  ]),
  _overdue('s1', 'BLUEWAVE AUTO SPARES -- RIVERBEND', 'Riverbend', 184850, 62750, 37, [(67, 'Sales · PT/1209', 62750)]),
  _overdue('s5', 'COMET LUBES -- LAKESIDE', 'Lakeside', 61200, 24900, 19, [(49, 'Sales · PT/1301', 24900)]),
  _overdue('s7', 'ORBIT MOTOR WORKS -- CORAL BAY', 'Lakeside', 33760, 18210, 8, [(38, 'Sales · PT/1352', 18210)]),
];

/// Unpaid bills older than 30 days for the same shops as the Overdue view.
class _Analytics implements AnalyticsRepository {
  // (shop, days ago, rupees): unpaid sales bills, no payments yet.
  static const _bills = [
    ('s2', 82, 51200),
    ('s2', 64, 37200),
    ('s2', 12, 64500),
    ('s1', 67, 62750),
    ('s1', 20, 121600),
    ('s5', 49, 24900),
    ('s5', 9, 36300),
    ('s7', 38, 18210),
    ('s7', 6, 15550),
    ('s3', 15, 96420),
    ('s4', 11, 74880),
    ('s6', 8, 48315),
  ];

  @override
  Future<BusinessPaymentSummary> summary(String companyId, {required int creditDays}) async {
    String rs(int r) => '$r.00';
    String bucket(int daysAgo) => switch (daysAgo - creditDays) {
      <= 0 => 'not_due',
      <= 30 => 'd1_30',
      <= 60 => 'd31_60',
      <= 90 => 'd61_90',
      _ => 'd90_plus',
    };
    Map<String, String> ageing(Iterable<(String, int, int)> bills) {
      final out = {for (final k in AgeBucket.values) k.code: 0};
      for (final b in bills) {
        out[bucket(b.$2)] = out[bucket(b.$2)]! + b.$3;
      }
      return out.map((k, v) => MapEntry(k, rs(v)));
    }

    var overdueTotal = 0, openTotal = 0, overdueShops = 0;
    final shops = <Map<String, dynamic>>[];
    for (final s in _shops.take(7)) {
      final mine = [
        for (final b in _bills)
          if (b.$1 == s.id) b,
      ];
      if (mine.isEmpty) continue;
      final open = mine.fold(0, (t, b) => t + b.$3);
      final late = [
        for (final b in mine)
          if (b.$2 > creditDays) b,
      ];
      final overdue = late.fold(0, (t, b) => t + b.$3);
      final maxLate = late.fold(0, (m, b) => b.$2 - creditDays > m ? b.$2 - creditDays : m);
      overdueTotal += overdue;
      openTotal += open;
      if (overdue > 0) overdueShops++;
      shops.add({
        'shop': {'id': s.id, 'name': s.name, 'site_name': s.siteName, 'opening': '0.00', 'receivable': rs(open)},
        'advance': '0.00',
        'overdue': rs(overdue),
        'open_amount': rs(open),
        'open_bills': mine.length,
        'max_days_overdue': maxLate,
        'oldest_open_bill_date': _d(mine.map((b) => b.$2).reduce((a, b) => a > b ? a : b)),
        'ageing': ageing(mine),
        'paid_bills': 0,
        'on_time_bills': 0,
        'last_payment_amount': '0.00',
        'computed_balance': rs(open),
        'reconciled': true,
      });
    }
    return BusinessPaymentSummary.fromJson({
      'credit_days': creditDays,
      'today': _d(0),
      'overdue': rs(overdueTotal),
      'overdue_shops': overdueShops,
      'open_amount': rs(openTotal),
      'ageing': ageing([
        for (final b in _bills)
          if (_shops.take(7).any((s) => s.id == b.$1)) b,
      ]),
      'shops': shops,
    });
  }

  @override
  Future<ShopPayments> shop(String shopId, {required int creditDays}) => throw UnimplementedError();
}

class _Dashboard implements DashboardRepository {
  @override
  Future<Dashboard> load(String companyId) async {
    final now = DateTime.now();
    return Dashboard(
      summary: const CompanySummary(
        companyId: 'co',
        companyName: 'Sunrise Distributors (FY 2026-27)',
        shops: 214,
        shopsWithDues: 96,
        totalOutstanding: Money(248641250),
        totalCredit: Money(11230000),
      ),
      syncState: SyncState(lastSuccessfulSyncAt: now.subtract(const Duration(minutes: 3))),
      monthSales: MonthSales(month: DateTime(now.year, now.month), amount: const Money(684215000), bills: 143),
      topDues: _shops.take(10).toList(),
    );
  }
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
  Future<StockList> items(String companyId) async => stockListOf([
    stockItem(id: 'i1', name: 'TYRE 145/80 R12 TL', group: 'Tyres', unit: 'Nos', qty: 1250, value: const Money(287500000)),
    stockItem(id: 'i2', name: 'TYRE 90/100-10 TL', group: 'Tyres', unit: 'Nos', qty: 642, value: const Money(96300000)),
    stockItem(id: 'i3', name: 'ENGINE OIL 20W40 1 L', group: 'Lubricants', unit: 'Ltr', qty: 388, value: const Money(15132000)),
    stockItem(id: 'i4', name: 'TUBE 3.00-17', group: 'Tubes', unit: 'Nos', qty: 14, reorder: 50, value: const Money(2940000)),
    stockItem(
      id: 'i5',
      name: 'BRAKE SHOE SET (2W)',
      group: 'Spares',
      unit: 'Set',
      qty: 9,
      reorder: 40,
      value: const Money(1782000),
    ),
    stockItem(id: 'i6', name: 'CHAIN SPROCKET KIT', group: 'Spares', unit: 'Kit', qty: 0),
  ]);
  @override
  Future<StockItem> item(String itemId) async => throw UnimplementedError();
  @override
  Future<List<ItemPurchase>> purchasesOf(String itemId) async => const [];
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
  staffName: 'Sam',
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
        companyName: 'Sunrise Distributors (FY 2026-27)',
        shops: _shops,
        detailShop: const ShopDetail(
          id: 's1',
          companyId: 'co',
          name: 'BLUEWAVE AUTO SPARES -- RIVERBEND',
          area: 'Riverbend',
          receivable: Money(18485000),
        ),
      ),
    ),
    dashboardRepositoryProvider.overrideWithValue(_Dashboard()),
    analyticsRepositoryProvider.overrideWithValue(_Analytics()),
    overdueRepositoryProvider.overrideWithValue(FakeOverdueRepository(_overdueShops, 'Sunrise Distributors (FY 2026-27)')),
    siteRepositoryProvider.overrideWithValue(
      FakeSiteRepository(
        sitesList: _sites,
        reportRows: const [
          SiteReportRow(
            siteId: 'site-riverbend',
            siteName: 'Riverbend',
            shops: 58,
            shopsWithDues: 31,
            outstanding: Money(84213000),
            advance: Money(1250000),
            sales: Money(192840000),
            returns: Money(2105000),
            collections: Money(161520000),
          ),
          SiteReportRow(
            siteId: 'site-hillview',
            siteName: 'Hillview',
            shops: 64,
            shopsWithDues: 29,
            outstanding: Money(76054250),
            advance: Money.zero,
            sales: Money(214330000),
            returns: Money(980000),
            collections: Money(198410000),
          ),
          SiteReportRow(
            siteId: 'site-lakeside',
            siteName: 'Lakeside',
            shops: 47,
            shopsWithDues: 22,
            outstanding: Money(52896000),
            advance: Money(980000),
            sales: Money(143600000),
            returns: Money.zero,
            collections: Money(127250000),
          ),
          SiteReportRow(
            siteId: 'site-greenfield',
            siteName: 'Greenfield',
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
          _task('1', 'BLUEWAVE AUTO SPARES -- RIVERBEND', 'Riverbend', VisitState.verified),
          _task('2', 'BRIGHT STAR AGENCIES -- SILVER OAK', 'Riverbend', VisitState.verified),
          _task('3', 'NOVA TYRES -- RIVERBEND', 'Riverbend', VisitState.verified),
          _task('4', 'PIONEER MOTOR STORES -- RIVERBEND', 'Riverbend', VisitState.pending),
          _task('5', 'GALAXY AUTOMOBILES -- RIVERBEND', 'Riverbend', VisitState.pending),
          _task('6', 'SUMMIT TYRE POINT -- PALM GROVE', 'Riverbend', VisitState.pending),
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
  tester.view.physicalSize = _play ? const Size(1080, 1920) : const Size(1080, 2400);
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
  // Captured at ×3 (full phone resolution); a golden file would be 1×.
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('test/marketing/out/${_play ? 'play/' : ''}$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
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
    testWidgets('staff dashboard', (t) => _shot(t, 'staff-dashboard', const DashboardScreen(), user: _staff));
    testWidgets('staff shops', (t) => _shot(t, 'staff-shops', const ShopsScreen(), user: _staff, nav: 1));
    testWidgets('staff stock', (t) => _shot(t, 'staff-stock', const StockScreen(), user: _staff, nav: 3));
  });
}
