import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../company/presentation/company_providers.dart';
import '../../company/presentation/company_switcher.dart';
import '../../home/account_button.dart';
import '../../home/refresh.dart';
import '../domain/shop.dart';
import 'shop_list_controller.dart';
import 'shop_tile.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const CompanyTitle(screen: 'Shops'),
        actions: [
          IconButton(tooltip: 'Sort', icon: const Icon(Icons.sort_rounded), onPressed: () => _showSort(context)),
          const AccountButton(),
        ],
      ),
      body: company == null
          ? const SizedBox.shrink()
          : ContentWidth(
              child: Column(
                children: [
                  Padding(
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
                  _FilterRow(companyId: company.id, filter: filter),
                  const Divider(height: 1),
                  Expanded(child: _ShopListView(companyId: company.id)),
                ],
              ),
            ),
    );
  }

  Future<void> _showSort(BuildContext context) {
    dismissKeyboard();
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final sort = ref.watch(shopFilterControllerProvider).sort;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Insets.xl, 0, Insets.xl, Insets.s),
                  child: Text('Sort by', style: context.text.titleMedium),
                ),
                RadioGroup<ShopSort>(
                  groupValue: sort,
                  onChanged: (s) {
                    if (s != null) ref.read(shopFilterControllerProvider.notifier).setSort(s);
                    Navigator.of(context).pop();
                  },
                  child: Column(
                    children: [for (final s in ShopSort.values) RadioListTile<ShopSort>(value: s, title: Text(s.label))],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
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
          for (final b in BalanceFilter.values.skip(1)) ...[
            FilterChip(
              label: Text(b.label),
              selected: filter.balance == b,
              onSelected: (on) => notifier.setBalance(on ? b : BalanceFilter.all),
            ),
            const SizedBox(width: Insets.s),
          ],
          FilterChip(
            avatar: const Icon(Icons.place_outlined, size: 18),
            label: Text(filter.areas.isEmpty ? 'Area' : '${filter.areas.length} area${filter.areas.length == 1 ? '' : 's'}'),
            selected: filter.areas.isNotEmpty,
            showCheckmark: false,
            onSelected: (_) => _pickAreas(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAreas(BuildContext context, WidgetRef ref) async {
    dismissKeyboard();
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => AreaPickerSheet(companyId: companyId, initial: filter.areas),
    );
    if (picked != null) ref.read(shopFilterControllerProvider.notifier).setAreas(picked);
  }
}

/// Multi-select of a company's areas; returns the chosen set (empty = all).
class AreaPickerSheet extends ConsumerStatefulWidget {
  const AreaPickerSheet({super.key, required this.companyId, required this.initial, this.title = 'Filter by area'});

  final String companyId;
  final Set<String> initial;
  final String title;

  @override
  ConsumerState<AreaPickerSheet> createState() => _AreaPickerSheetState();
}

class _AreaPickerSheetState extends ConsumerState<AreaPickerSheet> {
  late final Set<String> _selected = {...widget.initial};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final areas = ref.watch(companyAreasProvider(widget.companyId));
    final q = _query.trim().toLowerCase();
    // Keep the list above the keyboard while searching.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.xl, 0, Insets.s, 0),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title, style: context.text.titleMedium)),
                  TextButton(onPressed: () => setState(_selected.clear), child: const Text('Clear')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.l, Insets.xs, Insets.l, Insets.s),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search areas',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: switch (areas) {
                AsyncValue(:final value?) when value.isEmpty => const EmptyState(
                  icon: Icons.place_outlined,
                  title: 'No areas found',
                ),
                AsyncValue(:final value?) => ListView(
                  controller: scroll,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    for (final a in value)
                      if (q.isEmpty || a.toLowerCase().contains(q) || _selected.contains(a))
                        CheckboxListTile(
                          value: _selected.contains(a),
                          title: Text(areaLabel(a)),
                          onChanged: (on) => setState(() => on == true ? _selected.add(a) : _selected.remove(a)),
                        ),
                  ],
                ),
                AsyncValue(:final error?) => ErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(companyAreasProvider(widget.companyId)),
                ),
                _ => const SkeletonList(),
              },
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Insets.l),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: Text(_selected.isEmpty ? 'Show all areas' : 'Apply (${_selected.length})'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
