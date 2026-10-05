import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/app_failure.dart';
import '../data/shop_repository.dart';
import '../domain/shop.dart';

part 'shop_list_controller.g.dart';

/// The shop list's search/filter/sort; kept while the app runs.
@Riverpod(keepAlive: true)
class ShopFilterController extends _$ShopFilterController {
  @override
  ShopFilter build() => const ShopFilter();

  void setQuery(String q) => state = state.copyWith(query: q);
  void setBalance(BalanceFilter b) => state = state.copyWith(balance: b);
  void setSites(Set<String> siteIds) => state = state.copyWith(siteIds: siteIds);
  void setSort(ShopSort s) => state = state.copyWith(sort: s);
  void clear() => state = const ShopFilter();
}

enum ShopsView {
  all('All shops'),
  dues('Dues'),
  overdue('Overdue');

  const ShopsView(this.label);
  final String label;
}

/// Which list the Shops tab shows; opens on Dues and keeps the last choice
/// while the app runs.
@Riverpod(keepAlive: true)
class ShopsViewController extends _$ShopsViewController {
  @override
  ShopsView build() => ShopsView.dues;

  void set(ShopsView v) => state = v;
}

class ShopPage {
  const ShopPage({required this.items, required this.hasMore, this.loadingMore = false, this.loadMoreError});

  final List<ShopSummary> items;
  final bool hasMore;
  final bool loadingMore;
  final AppFailure? loadMoreError;

  ShopPage copyWith({List<ShopSummary>? items, bool? hasMore, bool? loadingMore, AppFailure? loadMoreError}) => ShopPage(
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: loadMoreError,
  );
}

/// Infinite-scroll list of shops for a company with the current filter.
@riverpod
class ShopList extends _$ShopList {
  int _nextPage = 0;

  @override
  Future<ShopPage> build(String companyId) async {
    final filter = ref.watch(shopFilterControllerProvider);
    _nextPage = 0;
    final items = await ref.watch(shopRepositoryProvider).page(companyId, filter, 0);
    _nextPage = 1;
    return ShopPage(items: items, hasMore: items.length == ShopRepository.pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore || state.isLoading) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    final filter = ref.read(shopFilterControllerProvider);
    final page = _nextPage;
    try {
      final more = await ref.read(shopRepositoryProvider).page(companyId, filter, page);
      if (!ref.mounted || filter != ref.read(shopFilterControllerProvider)) return;
      _nextPage = page + 1;
      state = AsyncData(ShopPage(items: [...current.items, ...more], hasMore: more.length == ShopRepository.pageSize));
    } catch (e) {
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: AppFailure.from(e)));
    }
  }
}
