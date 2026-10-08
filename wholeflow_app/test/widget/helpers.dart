import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wholeflow_app/core/errors/app_failure.dart';
import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/core/theme/app_theme.dart';
import 'package:wholeflow_app/features/analytics/data/analytics_repository.dart';
import 'package:wholeflow_app/features/analytics/domain/payment_analysis.dart';
import 'package:wholeflow_app/features/auth/data/auth_repository.dart';
import 'package:wholeflow_app/features/auth/domain/app_user.dart';
import 'package:wholeflow_app/features/company/data/company_repository.dart';
import 'package:wholeflow_app/features/company/domain/company.dart';
import 'package:wholeflow_app/features/dashboard/data/dashboard_repository.dart';
import 'package:wholeflow_app/features/dashboard/domain/dashboard_models.dart';
import 'package:wholeflow_app/features/outstanding/data/overdue_repository.dart';
import 'package:wholeflow_app/features/outstanding/domain/overdue_report.dart';
import 'package:wholeflow_app/features/shop_detail/data/transaction_repository.dart';
import 'package:wholeflow_app/features/shop_detail/domain/statement.dart';
import 'package:wholeflow_app/features/shops/data/shop_repository.dart';
import 'package:wholeflow_app/features/shops/domain/shop.dart';
import 'package:wholeflow_app/features/sites/data/site_repository.dart';
import 'package:wholeflow_app/features/sites/domain/site.dart';
import 'package:wholeflow_app/features/visits/data/shop_location_repository.dart';
import 'package:wholeflow_app/features/visits/domain/shop_location.dart';
import 'package:wholeflow_app/features/visits/data/visit_repository.dart';
import 'package:wholeflow_app/features/visits/domain/visit.dart';
import 'package:wholeflow_app/core/location/location_service.dart';

const owner = AppUser(id: 'owner-1', businessId: 'biz', role: UserRole.owner, name: 'Owner');
const staffUser = AppUser(id: 'staff-1', businessId: 'biz', role: UserRole.staff, name: 'Ravi');

Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  ThemeData? theme,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      retry: (_, _) => null,
      child: MaterialApp(theme: theme ?? AppTheme.light(), home: child),
    ),
  );
}

/// Like [pumpScreen], under a GoRouter: [child] over a base page, and any
/// other location shows its path, so tests can see where a screen navigated.
Future<void> pumpRoutedScreen(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.reset);
  // [child] is pushed over a base page, so screens that pop after saving can.
  final router = GoRouter(
    initialLocation: '/base',
    routes: [
      GoRoute(
        path: '/base',
        builder: (context, state) => const Scaffold(body: Text('base page')),
      ),
      GoRoute(path: '/screen', builder: (context, state) => child),
      GoRoute(
        path: '/:rest(.*)',
        builder: (context, state) => Scaffold(body: Text('at ${state.uri.path}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      retry: (_, _) => null,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  unawaited(router.push('/screen'));
  await tester.pump();
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.signInError, this.profile});

  final AppFailure? signInError;
  AppUser? profile;
  bool signedIn = false;

  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();
  @override
  bool get hasSession => signedIn;
  @override
  bool get mustChangePassword => false;
  @override
  Future<void> signIn({required String email, required String password}) async {
    if (signInError != null) throw signInError!;
    signedIn = true;
  }

  @override
  Future<void> signOut() async => signedIn = false;
  @override
  Future<AppUser?> loadProfile() async => profile;
  @override
  Future<void> changePassword(String newPassword) async {}
  @override
  Future<String?> businessName(String businessId) async => 'Test Business';
}

class FakeCompanyRepository implements CompanyRepository {
  FakeCompanyRepository({this.companies = const [], this.access = const [], this.areas = const []});

  final List<Company> companies;
  final List<CompanyAccess> access;
  final List<String> areas;

  @override
  Future<List<Company>> visibleCompanies() async => companies;
  @override
  Future<List<CompanyAccess>> accessOf(String userId) async => access.where((a) => a.userId == userId).toList();
  @override
  Future<List<String>> areasOf(String companyId) async => areas;
}

/// Returns canned pages; [pending] keeps the first page loading forever.
class FakeShopRepository implements ShopRepository {
  FakeShopRepository({this.shops = const [], this.error, this.pending = false, this.detailShop});

  final List<ShopSummary> shops;
  final Object? error;
  final bool pending;
  final ShopDetail? detailShop;
  final List<ShopFilter> requested = [];

  @override
  Future<List<ShopSummary>> page(String companyId, ShopFilter filter, int pageIndex) {
    requested.add(filter);
    if (pending) return Completer<List<ShopSummary>>().future;
    if (error != null) return Future.error(error!);
    return Future.value(pageIndex == 0 ? shops : const []);
  }

  @override
  Future<ShopDetail> detail(String shopId) async => detailShop!;
  @override
  Future<List<ShopSummary>> outstanding(String companyId) async => shops;
}

/// Sites in memory; records what the editor saves.
class FakeSiteRepository implements SiteRepository {
  FakeSiteRepository({this.sitesList = const [], this.shops = const [], this.reportRows = const []});

  List<Site> sitesList;
  final List<SiteShop> shops;
  final List<SiteReportRow> reportRows;
  final Map<String, Set<String>> saved = {};
  final List<String> created = [];

  @override
  Future<List<Site>> sites(String companyId) async => sitesList.where((s) => s.companyId == companyId).toList();
  @override
  Future<List<Site>> allSites() async => sitesList;
  @override
  Future<String> create(String companyId, String name, Set<String> shopIds) async {
    final id = 'site-${created.length + 1}';
    created.add(name);
    sitesList = [...sitesList, Site(id: id, companyId: companyId, name: name)];
    saved[id] = shopIds;
    return id;
  }

  @override
  Future<void> rename(String siteId, String name) async {}
  @override
  Future<void> delete(String siteId) async {}
  @override
  Future<void> setShops(String siteId, Set<String> shopIds) async => saved[siteId] = shopIds;
  @override
  Future<List<SiteShop>> companyShops(String companyId) async => shops;
  @override
  Future<List<ShopSummary>> siteShops(String siteId) async => const [];
  @override
  Future<List<SiteReportRow>> report(String companyId, DateTime from, DateTime to) async => reportRows;
}

/// A phone that is always at [reading].
class FakeLocationService implements LocationService {
  const FakeLocationService(this.reading, {this.devMode = false});

  final LocationReading reading;
  final bool devMode;

  @override
  Future<LocationReading> current({Duration timeout = const Duration(seconds: 20)}) async => reading;
  @override
  Future<bool> developerModeOn() async => devMode;
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> openDeveloperSettings() async {}
}

/// Tasks in memory; check-in answers with [answer] and records the call.
class FakeVisitRepository implements VisitRepository {
  FakeVisitRepository({this.taskList = const [], this.answer = const CheckInResult(result: 'verified')});

  List<VisitTask> taskList;
  CheckInResult answer;
  final List<(String, String?)> checkIns = [];
  final List<Map<String, Object?>> created = [];

  @override
  Future<void> ensureTasks(DateTime from, DateTime to) async {}
  @override
  Future<List<VisitTask>> tasks(DateTime from, DateTime to, {String? companyId, String? staffId}) async => taskList;
  @override
  Future<List<VisitPlan>> plans(String companyId) async => const [];
  @override
  Future<void> createPlans({
    required String siteId,
    required String staffId,
    DateTime? date,
    Set<int> weekdays = const {},
    DateTime? startsOn,
    DateTime? endsOn,
  }) async => created.add({'site': siteId, 'staff': staffId, 'date': date, 'weekdays': weekdays});
  @override
  Future<void> setPlanActive(String planId, bool active) async {}
  @override
  Future<void> deletePlan(String planId) async {}
  @override
  Future<ShopVisit?> visit(String visitId) async => null;
  @override
  Future<List<FailedAttempt>> failedAttempts(String taskId) async => const [];
  @override
  Future<CheckInResult> checkIn(String taskId, LocationReading r, {required bool developerMode, String? note}) async {
    checkIns.add((taskId, note));
    return answer;
  }

  @override
  Future<void> addNote(String visitId, String note) async {}
}

/// Pins by shop id; records reviews.
class FakeShopLocationRepository implements ShopLocationRepository {
  FakeShopLocationRepository({Map<String, ShopLocation>? pins, this.suggestions = const []}) : pins = pins ?? {};

  final Map<String, ShopLocation> pins;
  List<LocationSuggestion> suggestions;
  final List<(String, bool)> reviewed = [];

  @override
  Future<ShopLocation?> location(String shopId) async => pins[shopId];
  @override
  Future<void> setLocation(String shopId, double lat, double lng, int radiusM) async =>
      pins[shopId] = ShopLocation(shopId: shopId, latitude: lat, longitude: lng, radiusM: radiusM);
  @override
  Future<void> clearLocation(String shopId) async => pins.remove(shopId);
  @override
  Future<List<LocationSuggestion>> pendingSuggestions() async => suggestions;
  @override
  Future<void> review(String suggestionId, {required bool approve, int radiusM = ShopLocation.defaultRadius}) async {
    reviewed.add((suggestionId, approve));
    suggestions = suggestions.where((s) => s.id != suggestionId).toList();
  }
}

/// Returns [shops] for every credit period and records the periods asked for.
class FakeOverdueRepository implements OverdueRepository {
  FakeOverdueRepository([this.shops = const []]);

  final List<OverdueShop> shops;
  final List<int> requestedDays = [];

  @override
  Future<List<OverdueShop>> overdue(String companyId, {required int creditDays, required DateTime today}) async {
    requestedDays.add(creditDays);
    return shops;
  }
}

/// Answers like `GET /shops/{id}/statement`: running balances from
/// [opening]; the Tally balance is the computed one unless [tally] is given.
class FakeTransactionRepository implements TransactionRepository {
  FakeTransactionRepository([this.txns = const [], this.opening = Money.zero, this.tally]);

  final List<ShopTransaction> txns;
  final Money opening;
  final Money? tally;

  Map<String, dynamic> _json({DateTime? from, DateTime? to}) {
    String day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    String rs(Money m) => (m.paise / 100).toStringAsFixed(2);
    final ordered = [...txns]..sort((a, b) => a.transactionDate.compareTo(b.transactionDate));
    var running = opening, periodOpening = opening;
    final lines = <Map<String, dynamic>>[];
    for (final t in ordered) {
      running += t.amount;
      if (from != null && t.transactionDate.isBefore(from)) {
        periodOpening = running;
      } else if (to == null || !t.transactionDate.isAfter(to)) {
        lines.insert(0, {
          'id': t.id,
          'transaction_date': day(t.transactionDate),
          'voucher_type': t.voucherType,
          'voucher_number': t.voucherNumber,
          'category': t.category.name,
          'narration': t.narration,
          'debit': rs(t.debit),
          'credit': rs(t.credit),
          'amount': rs(t.amount),
          'balance_after': rs(running),
        });
      }
    }
    return {
      'from': from == null ? null : day(from),
      'to': to == null ? null : day(to),
      'opening': rs(periodOpening),
      'closing': lines.isEmpty ? rs(periodOpening) : lines.first['balance_after'],
      'ledger_opening': rs(opening),
      'tally_balance': rs(tally ?? running),
      'computed_balance': rs(running),
      'reconciled': (tally ?? running) == running,
      'lines': lines,
    };
  }

  @override
  Future<Statement> statement(String shopId) async => Statement.fromJson(_json());

  @override
  Future<PeriodStatement> period(String shopId, {DateTime? from, DateTime? to}) async =>
      PeriodStatement.fromJson(_json(from: from, to: to));
}

class FakeDashboardRepository implements DashboardRepository {
  FakeDashboardRepository({this.summaryRow, this.state, this.topDues = const []});

  final CompanySummary? summaryRow;
  final SyncState? state;
  final List<ShopSummary> topDues;

  @override
  Future<Dashboard> load(String companyId) async {
    final now = DateTime.now();
    return Dashboard(
      summary: summaryRow,
      syncState: state,
      monthSales: MonthSales(month: DateTime(now.year, now.month), amount: const Money(4567800), bills: 12),
      topDues: topDues,
    );
  }
}

/// Two shops relative to today, as the app API answers: one with a ₹10,000
/// bill from 50 days ago (unpaid), one that paid its bill 10 days after it.
class FakeAnalyticsRepository implements AnalyticsRepository {
  final calls = <int>[];

  static String _day(int daysAgo) {
    final t = DateTime.now().subtract(Duration(days: daysAgo));
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  static Map<String, dynamic> _ageing([String? bucket, String amount = '0.00']) => {
    for (final k in AgeBucket.values) k.code: k.code == bucket ? amount : '0.00',
  };

  static Map<String, dynamic> _prince(int days) {
    final late = 50 - days;
    return {
      'shop': {
        'id': 's1',
        'name': 'PRINCE TYRES -- RAJAKKAD',
        'site_name': 'Rajakkad',
        'opening': '0.00',
        'receivable': '10000.00',
      },
      'advance': '0.00',
      'overdue': late > 0 ? '10000.00' : '0.00',
      'open_amount': '10000.00',
      'open_bills': 1,
      'max_days_overdue': late > 0 ? late : 0,
      'oldest_open_bill_date': _day(50),
      'ageing': _ageing(late > 0 ? (late <= 30 ? 'd1_30' : 'd31_60') : 'not_due', '10000.00'),
      'paid_bills': 0,
      'on_time_bills': 0,
      'last_payment_amount': '0.00',
      'computed_balance': '10000.00',
      'reconciled': true,
    };
  }

  @override
  Future<BusinessPaymentSummary> summary(String companyId, {required int creditDays}) async {
    calls.add(creditDays);
    final prince = _prince(creditDays);
    final overdue = prince['overdue'] as String;
    return BusinessPaymentSummary.fromJson({
      'credit_days': creditDays,
      'today': _day(0),
      'overdue': overdue,
      'overdue_shops': overdue == '0.00' ? 0 : 1,
      'open_amount': '10000.00',
      'ageing': prince['ageing'],
      'on_time_rate': creditDays >= 10 ? 1.0 : 0.0,
      'avg_days_to_pay': 10.0,
      // A month ago the bill was 20 days old: not past 30 or 60 days.
      'overdue_month_ago': '0.00',
      'shops': [
        prince,
        {
          'shop': {'id': 's2', 'name': 'KERALA AUTO -- PALA', 'site_name': 'Pala', 'opening': '0.00', 'receivable': '0.00'},
          'advance': '0.00',
          'overdue': '0.00',
          'open_amount': '0.00',
          'open_bills': 0,
          'max_days_overdue': 0,
          'ageing': _ageing(),
          'paid_bills': 1,
          'on_time_bills': creditDays >= 10 ? 1 : 0,
          'on_time_rate': creditDays >= 10 ? 1.0 : 0.0,
          'avg_days_to_pay': 10.0,
          'avg_days_late': 0.0,
          'last_payment_date': _day(30),
          'last_payment_amount': '5000.00',
          'computed_balance': '0.00',
          'reconciled': true,
        },
      ],
    });
  }

  @override
  Future<ShopPayments> shop(String shopId, {required int creditDays}) async => ShopPayments.fromJson({
    ..._prince(creditDays),
    'credit_days': creditDays,
    'today': _day(0),
    'closed_bills': 0,
    'bills': [
      {
        'date': _day(50),
        'due': _day(50 - creditDays),
        'amount': '10000.00',
        'remaining': '10000.00',
        'voucher': 'Sales · 101',
        'allocations': [],
      },
    ],
  });
}
