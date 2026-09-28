import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../data/purchase_repository.dart';
import '../domain/purchase.dart';

class PurchasePage {
  const PurchasePage({required this.items, required this.hasMore, this.loadingMore = false, this.loadMoreError});

  final List<PurchaseSummary> items;
  final bool hasMore;
  final bool loadingMore;
  final AppFailure? loadMoreError;

  PurchasePage copyWith({bool? loadingMore, AppFailure? loadMoreError}) => PurchasePage(
    items: items,
    hasMore: hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: loadMoreError,
  );
}

/// Infinite-scroll list of purchase bills for a [PurchaseQuery].
class PurchaseList extends AsyncNotifier<PurchasePage> {
  PurchaseList(this.query);

  final PurchaseQuery query;
  int _nextPage = 0;

  @override
  Future<PurchasePage> build() async {
    _nextPage = 0;
    final items = await ref.watch(purchaseRepositoryProvider).page(query, 0);
    _nextPage = 1;
    return PurchasePage(items: items, hasMore: items.length == PurchaseRepository.pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore || state.isLoading) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    final page = _nextPage;
    try {
      final more = await ref.read(purchaseRepositoryProvider).page(query, page);
      if (!ref.mounted) return;
      _nextPage = page + 1;
      state = AsyncData(
        PurchasePage(items: [...current.items, ...more], hasMore: more.length == PurchaseRepository.pageSize),
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: AppFailure.from(e)));
    }
  }
}

final purchaseListProvider = AsyncNotifierProvider.autoDispose.family<PurchaseList, PurchasePage, PurchaseQuery>(
  PurchaseList.new,
);

final purchaseDetailProvider = FutureProvider.autoDispose.family<PurchaseDetail, String>(
  (ref, purchaseId) => ref.watch(purchaseRepositoryProvider).detail(purchaseId),
);

/// First day of the month [monthsBack] months before [now]'s month.
DateTime monthStart(DateTime now, {int monthsBack = 0}) => DateTime(now.year, now.month - monthsBack);

/// This month's and last month's purchase totals of a company.
final recentMonthsProvider = FutureProvider.autoDispose.family<List<MonthPurchases>, String>(
  (ref, companyId) =>
      ref.watch(purchaseRepositoryProvider).monthTotals(companyId, monthStart(DateTime.now(), monthsBack: 1)),
);

/// The last 12 months (this one included) of one supplier.
final supplierMonthsProvider = FutureProvider.autoDispose.family<List<MonthPurchases>, ({String companyId, String supplierId})>(
  (ref, arg) => ref
      .watch(purchaseRepositoryProvider)
      .monthTotals(arg.companyId, monthStart(DateTime.now(), monthsBack: 11), supplierId: arg.supplierId),
);
