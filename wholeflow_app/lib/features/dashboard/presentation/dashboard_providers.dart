import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../shops/domain/shop.dart';
import '../data/dashboard_repository.dart';
import '../domain/business_trend.dart';
import '../domain/dashboard_models.dart';

part 'dashboard_providers.g.dart';

/// The whole dashboard, fetched in one call; the providers below are its parts.
@riverpod
Future<Dashboard> dashboard(Ref ref, String companyId) => ref.watch(dashboardRepositoryProvider).load(companyId);

@riverpod
Future<CompanySummary?> companySummary(Ref ref, String companyId) async =>
    (await ref.watch(dashboardProvider(companyId).future)).summary;

@riverpod
Future<SyncState?> companySyncState(Ref ref, String companyId) async =>
    (await ref.watch(dashboardProvider(companyId).future)).syncState;

/// Null for staff who may not see the company's transactions.
@riverpod
Future<MonthSales?> monthSales(Ref ref, String companyId) async =>
    (await ref.watch(dashboardProvider(companyId).future)).monthSales;

@riverpod
Future<List<ShopSummary>> topDues(Ref ref, String companyId) async =>
    (await ref.watch(dashboardProvider(companyId).future)).topDues;

/// How many months the owner's trend covers (6 or 12). A view setting only.
final trendMonthsProvider = NotifierProvider<TrendMonths, int>(TrendMonths.new);

class TrendMonths extends Notifier<int> {
  @override
  int build() => 6;

  void set(int months) => state = months;
}

/// Owner: month-by-month sales, collections and purchases, and top buyers.
final businessTrendProvider = FutureProvider.autoDispose.family<BusinessTrend, String>((ref, companyId) {
  final months = ref.watch(trendMonthsProvider);
  return ref.watch(dashboardRepositoryProvider).trend(companyId, months: months);
});
