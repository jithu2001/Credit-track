import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
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
  Future<List<ShopSummary>> topDues(String companyId, {int limit = 10}) async => shops.take(limit).toList();
  @override
  Future<List<ShopSummary>> outstanding(String companyId) async => shops;
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

class FakeTransactionRepository implements TransactionRepository {
  FakeTransactionRepository([this.txns = const []]);

  final List<ShopTransaction> txns;

  @override
  Future<List<ShopTransaction>> forShop(String shopId) async => txns;
}

class FakeDashboardRepository implements DashboardRepository {
  FakeDashboardRepository({this.summaryRow, this.state});

  final CompanySummary? summaryRow;
  final SyncState? state;

  @override
  Future<CompanySummary?> summary(String companyId) async => summaryRow;
  @override
  Future<SyncState?> syncState(String companyId) async => state;
  @override
  Future<MonthSales> monthSales(String companyId, DateTime now) async =>
      MonthSales(month: DateTime(now.year, now.month), amount: const Money(4567800), bills: 12);
}

/// Two shops relative to today: one 20 days overdue, one paid on time.
class FakeAnalyticsRepository implements AnalyticsRepository {
  @override
  Future<AnalyticsData> load(String companyId) async {
    final today = DateTime.now();
    final d = DateTime(today.year, today.month, today.day);
    return AnalyticsData(
      booksFrom: d.subtract(const Duration(days: 365)),
      shops: const [
        ShopOpening(
          id: 's1',
          name: 'PRINCE TYRES -- RAJAKKAD',
          area: 'Rajakkad',
          opening: Money.zero,
          receivable: Money(1000000),
        ),
        ShopOpening(id: 's2', name: 'KERALA AUTO -- PALA', area: 'Pala', opening: Money.zero, receivable: Money.zero),
      ],
      txns: [
        PaymentTxn(
          shopId: 's1',
          date: d.subtract(const Duration(days: 50)),
          category: TxnCategory.sales,
          debit: const Money(1000000),
          credit: Money.zero,
          voucher: 'Sales · 101',
        ),
        PaymentTxn(
          shopId: 's2',
          date: d.subtract(const Duration(days: 40)),
          category: TxnCategory.sales,
          debit: const Money(500000),
          credit: Money.zero,
        ),
        PaymentTxn(
          shopId: 's2',
          date: d.subtract(const Duration(days: 30)),
          category: TxnCategory.receipts,
          debit: Money.zero,
          credit: const Money(500000),
        ),
      ],
    );
  }
}
