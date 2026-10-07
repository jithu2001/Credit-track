import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../auth/presentation/session_controller.dart';
import '../../home/refresh.dart';
import '../domain/stock_item.dart';
import 'inventory_providers.dart';
import 'stock_widgets.dart';

/// Searchable stock list of one company. Owners also see stock values.
class InventoryView extends ConsumerStatefulWidget {
  const InventoryView({super.key, required this.companyId});

  final String companyId;

  @override
  ConsumerState<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends ConsumerState<InventoryView> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  Timer? _debounce;
  StockFilter _filter = const StockFilter();

  /// Item ids picked in selection mode (owner); null = not selecting.
  Set<String>? _selected;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _filter = _filter.copyWith(query: value));
    });
  }

  void _clear() {
    _search.clear();
    ref.read(inventoryStatusFilterProvider.notifier).set(null);
    ref.read(inventoryBelowMinimumProvider.notifier).set(false);
    setState(() => _filter = StockFilter(sort: _filter.sort));
  }

  void _toggle(String id) => setState(() {
    final s = _selected ??= {};
    if (!s.remove(id)) s.add(id);
  });

  Future<void> _setMinimumForSelection(List<StockItem> all) async {
    final ids = _selected!;
    final picked = all.where((i) => ids.contains(i.id)).toList();
    if (picked.isEmpty) return;
    final units = {for (final i in picked) i.unit?.trim() ?? ''};
    final sameMin = {for (final i in picked) i.minQty};
    final choice = await askMinimum(
      context,
      title: picked.length == 1 ? picked.first.name : 'Minimum for ${plural(picked.length, 'item')}',
      subtitle: picked.length == 1 ? null : 'The same minimum is set on every selected item.',
      unit: units.length == 1 ? units.first : null,
      current: sameMin.length == 1 ? sameMin.first : null,
      canRemove: picked.any((i) => i.minQty != null),
    );
    if (choice == null || !mounted) return;
    try {
      await setStockMinimum(ref, widget.companyId, ids, choice.min);
      if (!mounted) return;
      setState(() => _selected = null);
      showMessage(
        context,
        choice.min == null
            ? 'Minimum removed from ${plural(picked.length, 'item')}'
            : 'Minimum set on ${plural(picked.length, 'item')}',
      );
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isOwner = ref.watch(currentUserProvider)?.isOwner ?? false;
    final items = ref.watch(stockItemsProvider(widget.companyId));
    final all = items.value ?? const <StockItem>[];
    final summary = StockSummary.of(all);
    final status = ref.watch(inventoryStatusFilterProvider);
    if (_filter.status != status) _filter = _filter.copyWith(status: () => status);
    final belowMinimum = ref.watch(inventoryBelowMinimumProvider);
    if (_filter.belowMinimum != belowMinimum) _filter = _filter.copyWith(belowMinimum: belowMinimum);
    final alerts = all.where((i) => i.atOrBelowMinimum).length;
    return ContentWidth(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, Insets.s),
            child: SearchBar(
              controller: _search,
              hintText: 'Search item, part no. or group',
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
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.s),
              children: [
                if (all.any((i) => i.hasMinimum) || _filter.belowMinimum) ...[
                  FilterChip(
                    key: const Key('below-minimum'),
                    label: Text('Below minimum ($alerts)'),
                    selected: _filter.belowMinimum,
                    onSelected: (on) => ref.read(inventoryBelowMinimumProvider.notifier).set(on),
                  ),
                  const SizedBox(width: Insets.s),
                ],
                for (final s in StockStatus.values.skip(1)) ...[
                  FilterChip(
                    label: Text(items.hasValue ? '${s.label} (${summary.byStatus[s]})' : s.label),
                    selected: _filter.status == s,
                    onSelected: (on) => ref.read(inventoryStatusFilterProvider.notifier).set(on ? s : null),
                  ),
                  const SizedBox(width: Insets.s),
                ],
                FilterChip(
                  avatar: const Icon(Icons.category_outlined, size: 18),
                  label: Text(_filter.group == null ? 'Group' : groupLabel(_filter.group)),
                  selected: _filter.group != null,
                  showCheckmark: false,
                  onSelected: all.isEmpty ? null : (_) => _pickGroup(context, all),
                ),
                const SizedBox(width: Insets.s),
                ActionChip(
                  avatar: const Icon(Icons.sort_rounded, size: 18),
                  label: const Text('Sort'),
                  onPressed: () => _pickSort(context, isOwner),
                ),
              ],
            ),
          ),
          if (_selected != null)
            _SelectionBar(
              count: _selected!.length,
              onSelectAll: () => setState(() => _selected = {for (final i in filterStock(all, _filter)) i.id}),
              onSetMinimum: _selected!.isEmpty ? null : () => _setMinimumForSelection(all),
              onClose: () => setState(() => _selected = null),
            ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => refreshCompanyData(ref),
              child: switch (items) {
                AsyncValue(:final value?) => _list(context, value, summary, isOwner),
                AsyncValue(:final error?) => _fill(
                  ErrorState(error: error, onRetry: () => ref.invalidate(stockItemsProvider(widget.companyId))),
                ),
                _ => const SkeletonList(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _fill(Widget child) => LayoutBuilder(
    builder: (context, c) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(height: c.maxHeight, child: child),
    ),
  );

  Widget _list(BuildContext context, List<StockItem> all, StockSummary summary, bool isOwner) {
    if (all.isEmpty) {
      return _fill(
        const EmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'No stock items yet',
          message: 'Stock items appear here after the WholeFlow sync service reads them from Tally.',
        ),
      );
    }
    final shown = filterStock(all, _filter);
    if (shown.isEmpty) {
      return _fill(
        EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No items match',
          message: 'Try a different search or clear the filters.',
          action: OutlinedButton(onPressed: _clear, child: const Text('Clear filters')),
        ),
      );
    }
    final shownValue = shown.fold(Money.zero, (sum, i) => sum + (i.closingValue ?? Money.zero));
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: shown.length + 1,
      separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(height: 1, indent: Insets.l),
      itemBuilder: (context, i) {
        if (i == 0) {
          return _SummaryLine(
            count: shown.length,
            total: all.length,
            value: isOwner ? shownValue : null,
            syncedAt: summary.syncedAt,
            hint: isOwner && _selected == null ? 'Long-press items to set minimum stock' : null,
          );
        }
        final item = shown[i - 1];
        return StockItemTile(
          item: item,
          selected: _selected?.contains(item.id),
          onSelect: () => _toggle(item.id),
          onLongPress: isOwner && _selected == null ? () => _toggle(item.id) : null,
        );
      },
    );
  }

  Future<void> _pickGroup(BuildContext context, List<StockItem> all) async {
    dismissKeyboard();
    final groups = stockGroups(all);
    // Sheets can't return null for "all groups", so that choice is a sentinel.
    const allGroups = '\u0000all';
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scroll) => RadioGroup<String>(
          groupValue: _filter.group ?? allGroups,
          onChanged: (g) => Navigator.of(context).pop(g),
          child: ListView(
            controller: scroll,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Insets.xl, 0, Insets.xl, Insets.s),
                child: Text('Stock group', style: context.text.titleMedium),
              ),
              const RadioListTile<String>(value: allGroups, title: Text('All groups')),
              for (final g in groups) RadioListTile<String>(value: g, title: Text(groupLabel(g))),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _filter = _filter.copyWith(group: () => picked == allGroups ? null : picked));
  }

  Future<void> _pickSort(BuildContext context, bool isOwner) async {
    dismissKeyboard();
    final options = [
      for (final s in StockSort.values)
        if (isOwner || s != StockSort.valueDesc) s,
    ];
    final picked = await showModalBottomSheet<StockSort>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.xl, 0, Insets.xl, Insets.s),
              child: Text('Sort by', style: context.text.titleMedium),
            ),
            RadioGroup<StockSort>(
              groupValue: _filter.sort,
              onChanged: (s) => Navigator.of(context).pop(s),
              child: Column(
                children: [for (final s in options) RadioListTile<StockSort>(value: s, title: Text(s.label))],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _filter = _filter.copyWith(sort: picked));
  }
}

/// Shown while picking items to set one minimum on all of them.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.count, required this.onSelectAll, required this.onSetMinimum, required this.onClose});

  final int count;
  final VoidCallback onSelectAll;
  final VoidCallback? onSetMinimum;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Insets.xs, Insets.xs, Insets.m, Insets.xs),
        child: Row(
          children: [
            IconButton(tooltip: 'Stop selecting', icon: const Icon(Icons.close_rounded), onPressed: onClose),
            Expanded(
              child: Text(
                count == 0 ? 'Select items' : '$count selected',
                style: context.text.titleSmall?.copyWith(color: context.colors.onSecondaryContainer),
              ),
            ),
            IconButton(tooltip: 'Select all shown', icon: const Icon(Icons.select_all_rounded), onPressed: onSelectAll),
            const SizedBox(width: Insets.xs),
            FilledButton.tonal(key: const Key('set-minimum'), onPressed: onSetMinimum, child: const Text('Set minimum')),
          ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.count, required this.total, this.value, this.syncedAt, this.hint});

  final int count;
  final int total;
  final Money? value;
  final DateTime? syncedAt;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final parts = [
      count == total ? plural(total, 'item') : '$count of ${plural(total, 'item')}',
      if (value != null) 'Value ${formatInrCompact(value!)}',
      if (syncedAt != null) 'Synced ${timeAgo(syncedAt!)}',
      ?hint,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.l, Insets.m, Insets.l, Insets.xs),
      child: Text(parts.join(' · '), style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
    );
  }
}
