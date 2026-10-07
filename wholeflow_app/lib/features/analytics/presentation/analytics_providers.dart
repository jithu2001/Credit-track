import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/money/money.dart';
import '../data/analytics_repository.dart';
import '../domain/payment_analysis.dart';

part 'analytics_providers.g.dart';

const defaultCreditDays = 30;
const creditDayPresets = [15, 30, 45, 60, 90];

/// The credit period filter. A view setting only: kept in memory, never saved.
@Riverpod(keepAlive: true)
class CreditDays extends _$CreditDays {
  @override
  int build() => defaultCreditDays;

  void set(int days) => state = days.clamp(1, 365);
}

enum AnalyticsSort {
  slowestPayer('Slowest payers first'),
  overdueAmount('Most overdue first'),
  name('Name A–Z');

  const AnalyticsSort(this.label);
  final String label;
}

@Riverpod(keepAlive: true)
class AnalyticsSortController extends _$AnalyticsSortController {
  @override
  AnalyticsSort build() => AnalyticsSort.slowestPayer;

  void set(AnalyticsSort s) => state = s;
}

/// Raw data for a company; kept while the app runs, reloaded on refresh.
@Riverpod(keepAlive: true)
Future<AnalyticsData> analyticsData(Ref ref, String companyId) => ref.watch(analyticsRepositoryProvider).load(companyId);

/// FIFO analysis with the current credit days. Recomputed on the device when
/// the filter changes; the data is not fetched again.
@riverpod
Future<BusinessPaymentSummary> paymentSummary(Ref ref, String companyId) async {
  final data = await ref.watch(analyticsDataProvider(companyId).future);
  final days = ref.watch(creditDaysProvider);
  return analyseBusiness(shops: data.shops, txns: data.txns, creditDays: days, booksFrom: data.booksFrom, today: DateTime.now());
}

/// Overdue 30 days ago with the same credit period, for the trend line.
@riverpod
Future<Money?> overdueMonthAgo(Ref ref, String companyId) async {
  final data = await ref.watch(analyticsDataProvider(companyId).future);
  final days = ref.watch(creditDaysProvider);
  return overdueDaysAgo(shops: data.shops, txns: data.txns, creditDays: days, booksFrom: data.booksFrom, today: DateTime.now());
}

List<ShopPaymentProfile> sortProfiles(List<ShopPaymentProfile> shops, AnalyticsSort sort) {
  int byName(ShopPaymentProfile a, ShopPaymentProfile b) => a.shop.name.toLowerCase().compareTo(b.shop.name.toLowerCase());
  final list = [...shops];
  switch (sort) {
    case AnalyticsSort.slowestPayer:
      // Shops that never paid go last: there is nothing to measure.
      list.sort((a, b) {
        final x = a.avgDaysToPay, y = b.avgDaysToPay;
        if (x == null && y == null) return b.overdue.compareTo(a.overdue);
        if (x == null) return 1;
        if (y == null) return -1;
        final c = y.compareTo(x);
        return c != 0 ? c : byName(a, b);
      });
    case AnalyticsSort.overdueAmount:
      list.sort((a, b) {
        final c = b.overdue.compareTo(a.overdue);
        return c != 0 ? c : byName(a, b);
      });
    case AnalyticsSort.name:
      list.sort(byName);
  }
  return list;
}
