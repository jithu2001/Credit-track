import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wholeflow_app/core/api/api_client.dart';
import 'package:wholeflow_app/core/location/location_service.dart';
import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/features/analytics/data/analytics_repository.dart';
import 'package:wholeflow_app/features/auth/domain/app_user.dart';
import 'package:wholeflow_app/features/company/data/company_repository.dart';
import 'package:wholeflow_app/features/dashboard/data/dashboard_repository.dart';
import 'package:wholeflow_app/features/inventory/data/inventory_repository.dart';
import 'package:wholeflow_app/features/inventory/domain/stock_item.dart';
import 'package:wholeflow_app/features/outstanding/data/overdue_repository.dart';
import 'package:wholeflow_app/features/purchases/data/purchase_repository.dart';
import 'package:wholeflow_app/features/shop_detail/data/transaction_repository.dart';
import 'package:wholeflow_app/features/shops/data/shop_repository.dart';
import 'package:wholeflow_app/features/shops/domain/shop.dart';
import 'package:wholeflow_app/features/sites/data/site_repository.dart';
import 'package:wholeflow_app/features/staff/data/staff_repository.dart';
import 'package:wholeflow_app/features/subscription/domain/service_status.dart';
import 'package:wholeflow_app/features/suppliers/data/supplier_repository.dart';
import 'package:wholeflow_app/features/sync_health/data/sync_health_repository.dart';
import 'package:wholeflow_app/features/visits/data/shop_location_repository.dart';
import 'package:wholeflow_app/features/visits/data/visit_repository.dart';

/// The contract between the app API and the app: every repository parses the
/// real answers the Go server gave in its integration test
/// (test/fixtures/api/*.json, written by
/// `WF_WRITE_FIXTURES=1 WF_TEST_PG=… go test ./internal/appapi` in WholeFlow/).
/// A field renamed on either side fails here, not on a phone.
void main() {
  // (method, path after /api/v1/, fixture)
  final routes = <(String, RegExp, String)>[
    ('GET', RegExp(r'^payments$'), 'payments'),
    ('GET', RegExp(r'^payments/shops/[^/]+$'), 'payments_shop'),
    ('GET', RegExp(r'^dashboard$'), 'dashboard'),
    ('GET', RegExp(r'^shops$'), 'shops'),
    ('GET', RegExp(r'^shops/[^/]+$'), 'shop_detail'),
    ('GET', RegExp(r'^shops/[^/]+/location$'), 'shop_location'),
    ('GET', RegExp(r'^reports/outstanding$'), 'report_outstanding'),
    ('GET', RegExp(r'^reports/overdue$'), 'report_overdue'),
    ('GET', RegExp(r'^reports/sites$'), 'report_sites'),
    ('GET', RegExp(r'^stock$'), 'stock'),
    ('GET', RegExp(r'^stock/[^/]+$'), 'stock_item'),
    ('GET', RegExp(r'^stock/[^/]+/purchases$'), 'stock_item_purchases'),
    ('PUT', RegExp(r'^stock/minimum$'), 'stock_minimum'),
    ('GET', RegExp(r'^purchases$'), 'purchases'),
    ('GET', RegExp(r'^purchases/months$'), 'purchase_months'),
    ('GET', RegExp(r'^purchases/[^/]+$'), 'purchase_detail'),
    ('GET', RegExp(r'^suppliers$'), 'suppliers'),
    ('GET', RegExp(r'^suppliers/[^/]+$'), 'supplier_detail'),
    ('GET', RegExp(r'^me$'), 'me'),
    ('GET', RegExp(r'^me/access$'), 'me_access'),
    ('GET', RegExp(r'^companies$'), 'companies'),
    ('GET', RegExp(r'^companies/[^/]+/areas$'), 'company_areas'),
    ('GET', RegExp(r'^companies/[^/]+/site-shops$'), 'company_site_shops'),
    ('GET', RegExp(r'^service-status$'), 'service_status'),
    ('GET', RegExp(r'^sync/connections$'), 'sync_connections'),
    ('GET', RegExp(r'^sync/logs$'), 'sync_logs'),
    ('GET', RegExp(r'^sites$'), 'sites'),
    ('POST', RegExp(r'^sites$'), 'site_created'),
    ('GET', RegExp(r'^sites/[^/]+/shops$'), 'site_shops'),
    ('GET', RegExp(r'^location-suggestions$'), 'location_suggestions'),
    ('GET', RegExp(r'^visits/tasks$'), 'visit_tasks'),
    ('GET', RegExp(r'^visits/tasks/[^/]+/failed-attempts$'), 'failed_attempts'),
    ('POST', RegExp(r'^visits/tasks/[^/]+/check-in$'), 'check_in'),
    ('GET', RegExp(r'^visits/plans$'), 'visit_plans'),
    ('GET', RegExp(r'^visits/[^/]+$'), 'visit'),
    ('GET', RegExp(r'^staff$'), 'staff'),
    ('POST', RegExp(r'^staff$'), 'staff_created'),
  ];
  final served = <String>{};
  final api = ApiClient(
    baseUrl: 'https://api.example.test/b/apitest',
    token: () async => 'token',
    client: MockClient((req) async {
      final path = req.url.path.split('/api/v1/').last;
      if (RegExp(r'^shops/[^/]+/statement$').hasMatch(path)) {
        final name = req.url.queryParameters.containsKey('from') ? 'statement_period' : 'statement';
        served.add(name);
        return http.Response.bytes(File('test/fixtures/api/$name.json').readAsBytesSync(), 200);
      }
      for (final (method, pattern, name) in routes) {
        if (req.method == method && pattern.hasMatch(path)) {
          served.add(name);
          return http.Response.bytes(File('test/fixtures/api/$name.json').readAsBytesSync(), 200);
        }
      }
      return http.Response('{"error":{"code":"NOT_FOUND","message":"no fixture for ${req.method} $path"}}', 404);
    }),
  );

  test('payments, statement, dashboard', () async {
    final summary = await AnalyticsRepository(api).summary('c', creditDays: 30);
    expect(summary.overdue, const Money(110000));
    expect(summary.shops.first.shop.siteName, 'Town');
    expect(summary.overdueMonthAgo, const Money(150000));
    final shop = await AnalyticsRepository(api).shop('s', creditDays: 30);
    expect(shop.profile.bills.first.isOpening, isTrue);
    expect(shop.profile.bills.first.allocations, isNotEmpty);

    final statement = await TransactionRepository(api).statement('s');
    expect(statement.newestFirst.first.transaction.voucherNumber, 'R1');
    expect(statement.reconciled, isTrue);
    final period = await TransactionRepository(api).period('s', from: DateTime(2026, 6), to: DateTime(2026, 6, 30));
    expect(period.opening, const Money(150000));
    expect(period.lines, hasLength(1));

    final dashboard = await DashboardRepository(api).load('c');
    expect(dashboard.summary!.totalOutstanding, const Money(110000));
    expect(dashboard.syncState!.lastSuccessfulSyncAt, isNotNull);
    expect(dashboard.monthSales!.bills, 1);
    expect(dashboard.topDues.single.siteName, 'Town');
  });

  test('shops and reports', () async {
    final shops = await ShopRepository(api).page('c', const ShopFilter(), 0);
    expect(shops.map((s) => s.name), contains('Alpha Stores'));
    final detail = await ShopRepository(api).detail('s');
    expect(detail.openingBalance, const Money(100000));
    expect(detail.siteName, 'Town');
    final outstanding = await ShopRepository(api).outstandingReport('c');
    expect(outstanding.total, const Money(110000));
    expect(outstanding.groups.single.site, 'Town');
    final overdue = await OverdueRepository(api).report('c', creditDays: 30);
    expect(overdue.groups.single.shops.single.bills, hasLength(2));
    final sites = await SiteRepository(api).report('c', DateTime(2026, 4), DateTime(2026, 7, 31));
    expect(sites, isNotEmpty);
  });

  test('stock, purchases, suppliers', () async {
    final stock = await InventoryRepository(api).items('c');
    expect(stock.items.map((i) => i.status), containsAll([StockStatus.low, StockStatus.zero]));
    expect(stock.alerts, hasLength(2));
    expect(stock.summary.value, const Money(30000));
    final item = await InventoryRepository(api).item('i');
    expect(item.name, 'TYRE');
    final bills = await InventoryRepository(api).purchasesOf('i');
    expect(bills.single.qty, 10);
    await InventoryRepository(api).setMinimum('c', ['i'], 4);

    final purchases = await PurchaseRepository(api).page((companyId: 'c', search: '', supplierId: null), 0);
    expect(purchases.single.voucherNumber, 'PB/1');
    final bill = await PurchaseRepository(api).detail('p');
    expect(bill.lines.single.itemName, 'TYRE');
    final months = await PurchaseRepository(api).monthTotals('c', DateTime(2026));
    expect(months.single.month, DateTime(2026, 7));
    final suppliers = await SupplierRepository(api).all('c');
    expect(suppliers.single.payable, const Money(250000));
    expect((await SupplierRepository(api).detail('s')).name, 'Supplier One');
  });

  test('profile, companies, subscription, sync', () async {
    final me = await api.get('me');
    expect(AppUser.fromJson(me['user'] as Map<String, dynamic>).isOwner, isTrue);
    expect(me['business_name'], 'API Biz');
    expect((await CompanyRepository(api).visibleCompanies()).single.companyName, 'API Co');
    expect((await CompanyRepository(api).accessOf('u')).single.canViewTransactions, isFalse);
    expect(await CompanyRepository(api).areasOf('c'), isEmpty);
    final status = (await api.get('service-status'))['service_status'];
    expect(status == null || ServiceStatus.fromJson(status as Map<String, dynamic>).status.isNotEmpty, isTrue);
    expect((await SyncHealthRepository(api).connections()).single.hostname, 'SHOP-PC');
    expect((await SyncHealthRepository(api).recentLogs()).single.recordsProcessed, 12);
  });

  test('sites, locations, visits, staff', () async {
    final sites = SiteRepository(api);
    expect((await sites.sites('c')).map((s) => s.name), contains('Town'));
    expect(await sites.create('c', 'Hills', {'s'}), isNotEmpty);
    expect((await sites.siteShops('x')).single.name, 'Beta Traders');
    expect(await sites.companyShops('c'), hasLength(2));

    final location = await ShopLocationRepository(api).location('s');
    expect(location!.radiusM, 50);
    expect(await ShopLocationRepository(api).pendingSuggestions(), isEmpty);

    final visits = VisitRepository(api);
    final tasks = await visits.tasks(DateTime(2026, 10, 8), DateTime(2026, 10, 8));
    expect(tasks.single.shopName, 'Alpha Stores');
    expect((await visits.plans('c')).single.siteName, 'Town');
    final result = await visits.checkIn(
      't',
      const LocationReading(latitude: 9.85, longitude: 76.97, accuracyMeters: 8, isMocked: false),
      developerMode: false,
    );
    expect(result, isNotNull);
    expect(await visits.visit('v'), isNotNull);
    expect(await visits.failedAttempts('t'), isEmpty);

    final staff = await StaffRepository(api).members();
    expect(staff.first.isOwner, isTrue);
    final limited = staff.firstWhere((m) => m.companies.any((c) => !c.fullCompany));
    expect(limited.companies.single.siteIds, isNotEmpty);
    expect(
      await StaffRepository(api).createStaff(name: 'N', email: 'n@new.test', password: 'secret123', companies: const []),
      isNotEmpty,
    );
  });

  tearDownAll(() {
    // Every fixture the server wrote is read by some repository.
    final written = {for (final f in Directory('test/fixtures/api').listSync()) f.uri.pathSegments.last.replaceAll('.json', '')}
      ..removeWhere((name) => name.startsWith('auth_')); // read by auth_contract_test.dart
    expect(written.difference(served), isEmpty, reason: 'fixtures no repository reads');
  });
}
