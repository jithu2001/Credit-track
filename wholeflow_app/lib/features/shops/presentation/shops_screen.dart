import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/multi_picker_sheet.dart';
import '../../../core/widgets/states.dart';
import '../../company/presentation/company_providers.dart';
import '../../company/presentation/company_switcher.dart';
import '../../home/account_button.dart';
import '../../home/refresh.dart';
import '../../outstanding/presentation/outstanding_views.dart';
import '../../sites/presentation/site_providers.dart';
import '../domain/shop.dart';
import 'shop_list_controller.dart';
import 'shop_tile.dart';

/// The Shops tab: every shop (All shops), shops that owe money grouped by site
/// (Dues), and shops past the credit period (Overdue), with one search.
class ShopsScreen extends ConsumerStatefulWidget {
  const ShopsScreen({super.key});

  @override
  ConsumerState<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends ConsumerState<ShopsScreen> {
  late final TextEditingController _search = TextEditingController(text: ref.read(shopFilterControllerProvider).query);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(shopFilterControllerProvider.notifier).setQuery(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(activeCompanyProvider).value;
    final filter = ref.watch(shopFilterControllerProvider);
    final view = ref.watch(shopsViewControllerProvider);
    final dues = company == null || view != ShopsView.dues ? null : ref.watch(outstandingReportProvider(company));
    final overdue = company == null || view != ShopsView.overdue ? null : ref.watch(overdueReportProvider(company));
    // Share always sends the whole report, not just the search matches.
    final VoidCallback? onShare = switch (view) {
      ShopsView.all => null,
      ShopsView.dues => switch (dues?.value) {
        final r? when r.groups.isNotEmpty => () => shareDuesReport(context, r),
        _ => null,
      },
      ShopsView.overdue => switch (overdue?.value) {
        final r? when r.groups.isNotEmpty => () => shareOverdueReport(context, r),
        _ => null,
      },
    };
    final searching = filter.query.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const CompanyTitle(screen: 'Shops'),
        actions: [
          if (view != ShopsView.dues)
            IconButton(tooltip: 'Sort', icon: const Icon(Icons.sort_rounded), onPressed: () => _showSort(context, view)),
          if (view != ShopsView.all)
            IconButton(tooltip: 'Share report', icon: const Icon(Icons.share_rounded), onPressed: onShare),
          const AccountButton(),
        ],
      ),
      body: company == null
          ? const SizedBox.shrink()
          : Column(
              children: [
                ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, 0),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ShopsView>(
                        key: const Key('shops-view'),
                        segments: [for (final v in ShopsView.values) ButtonSegment(value: v, label: Text(v.label))],
                        selected: {view},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => ref.read(shopsViewControllerProvider.notifier).set(s.first),
                      ),
                    ),
                  ),
                ),
                ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, Insets.s),
                    child: SearchBar(
                      controller: _search,
                      hintText: 'Search name, phone or area',
                      leading: const Icon(Icons.search_rounded),
                      trailing: [
                        if (_search.text.isNotEmpty)
                          IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _search.clear();
                              _onSearch('');
                              setState(() {});
                            },
                          ),
                      ],
                      onChanged: (v) {
                        setState(() {});
                        _onSearch(v);
                      },
                      elevation: const WidgetStatePropertyAll(0),
                    ),
                  ),
                ),
                if (view == ShopsView.all) ...[
                  ContentWidth(
                    child: _FilterRow(companyId: company.id, filter: filter),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ContentWidth(child: _ShopListView(companyId: company.id)),
                  ),
                ] else
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => refreshCompanyData(ref),
                      child: switch (view) {
                        ShopsView.overdue => ContentWidth(
                          child: OverdueView(
                            report: overdue!.whenData((r) => filterOverdueReport(r, filter.query)),
                            searching: searching,
                            sort: ref.watch(overdueSortControllerProvider),
                            onRetry: () => ref.invalidate(overdueReportProvider(company)),
                          ),
                        ),
                        _ => DuesView(
                          company: company,
                          report: dues!.whenData((r) => filterDuesReport(r, filter.query)),
                          searching: searching,
                        ),
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _showSort(BuildContext context, ShopsView view) {
    dismissKeyboard();
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Insets.xl, 0, Insets.xl, Insets.s),
                child: Text('Sort by', style: context.text.titleMedium),
              ),
              if (view == ShopsView.overdue)
                _SortOptions<OverdueSort>(
                  values: OverdueSort.values,
                  selected: ref.watch(overdueSortControllerProvider),
                  label: (s) => s.label,
                  onSelected: ref.read(overdueSortControllerProvider.notifier).set,
                )
              else
                _SortOptions<ShopSort>(
                  values: ShopSort.values,
                  selected: ref.watch(shopFilterControllerProvider).sort,
                  label: (s) => s.label,
                  onSelected: ref.read(shopFilterControllerProvider.notifier).setSort,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Radio list for a sort sheet; picking one closes the sheet.
class _SortOptions<T> extends StatelessWidget {
  const _SortOptions({required this.values, required this.selected, required this.label, required this.onSelected});

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => RadioGroup<T>(
    groupValue: selected,
    onChanged: (v) {
      if (v != null) onSelected(v);
      Navigator.of(context).pop();
    },
    child: Column(
      children: [for (final v in values) RadioListTile<T>(value: v, title: Text(label(v)))],
    ),
  );
}

class _FilterRow extends ConsumerWidget {
  const _FilterRow({required this.companyId, required this.filter});

  final String companyId;
  final ShopFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(shopFilterControllerProvider.notifier);
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.s),
        children: [
          // "Owes us" is the Dues view.
          for (final b in const [BalanceFilter.credit, BalanceFilter.settled]) ...[
            FilterChip(
              label: Text(b.label),
              selected: filter.balance == b,
              onSelected: (on) => notifier.setBalance(on ? b : BalanceFilter.all),
            ),
            const SizedBox(width: Insets.s),
          ],
          FilterChip(
            avatar: const Icon(Icons.location_city_outlined, size: 18),
            label: Text(filter.siteIds.isEmpty ? 'Site' : plural(filter.siteIds.length, 'site')),
            selected: filter.siteIds.isNotEmpty,
            showCheckmark: false,
            onSelected: (_) => _pickSites(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSites(BuildContext context, WidgetRef ref) async {
    final picked = await showMultiPicker(
      context,
      (context) => Consumer(
        builder: (context, ref, _) {
          final sites = ref.watch(companySitesProvider(companyId));
          return MultiPickerSheet(
            title: 'Filter by site',
            searchHint: 'Search sites',
            initial: filter.siteIds,
            options: sites.value == null
                ? null
                : [for (final s in sites.value!) (id: s.id, label: s.name), (id: ShopFilter.noSite, label: 'No site')],
            error: sites.error,
            onRetry: () => ref.invalidate(companySitesProvider(companyId)),
            applyLabel: (n) => n == 0 ? 'Show all sites' : 'Apply ($n)',
          );
        },
      ),
    );
    if (picked != null) ref.read(shopFilterControllerProvider.notifier).setSites(picked);
  }
}

class _ShopListView extends ConsumerWidget {
  const _ShopListView({required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(shopListProvider(companyId));
    return RefreshIndicator(
      onRefresh: () => refreshCompanyData(ref),
      child: switch (list) {
        AsyncValue(:final value?) when value.items.isEmpty => LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: c.maxHeight,
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No shops match',
                message: 'Try a different search or clear the filters.',
                action: OutlinedButton(
                  onPressed: () => ref.read(shopFilterControllerProvider.notifier).clear(),
                  child: const Text('Clear filters'),
                ),
              ),
            ),
          ),
        ),
        AsyncValue(:final value?) => NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 600) ref.read(shopListProvider(companyId).notifier).loadMore();
            return false;
          },
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: value.items.length + (value.hasMore || value.loadMoreError != null ? 1 : 0),
            separatorBuilder: (_, _) => const Divider(height: 1, indent: Insets.l),
            itemBuilder: (context, i) {
              if (i < value.items.length) return ShopTile(shop: value.items[i]);
              if (value.loadMoreError != null) {
                return Padding(
                  padding: const EdgeInsets.all(Insets.l),
                  child: Column(
                    children: [
                      Text(value.loadMoreError!.message, textAlign: TextAlign.center),
                      TextButton(
                        onPressed: () => ref.read(shopListProvider(companyId).notifier).loadMore(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              return const SkeletonTile();
            },
          ),
        ),
        AsyncValue(:final error?) => LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: c.maxHeight,
              child: ErrorState(error: error, onRetry: () => ref.invalidate(shopListProvider(companyId))),
            ),
          ),
        ),
        _ => const SkeletonList(),
      },
    );
  }
}
