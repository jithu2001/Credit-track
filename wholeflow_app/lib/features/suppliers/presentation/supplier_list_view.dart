import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../domain/supplier.dart';
import 'payable_text.dart';
import 'supplier_providers.dart';

/// Searchable supplier list of one company (owner only).
class SupplierListView extends ConsumerStatefulWidget {
  const SupplierListView({super.key, required this.companyId});

  final String companyId;

  @override
  ConsumerState<SupplierListView> createState() => _SupplierListViewState();
}

class _SupplierListViewState extends ConsumerState<SupplierListView> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  PayableFilter _filter = PayableFilter.all;
  SupplierSort _sort = SupplierSort.payableDesc;

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
      if (mounted) setState(() => _query = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final suppliers = ref.watch(suppliersProvider(widget.companyId));
    return ContentWidth(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, Insets.s),
            child: SearchBar(
              controller: _search,
              hintText: 'Search name, phone or GSTIN',
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
                for (final f in PayableFilter.values.skip(1)) ...[
                  FilterChip(
                    label: Text(f.label),
                    selected: _filter == f,
                    onSelected: (on) => setState(() => _filter = on ? f : PayableFilter.all),
                  ),
                  const SizedBox(width: Insets.s),
                ],
                ActionChip(
                  avatar: const Icon(Icons.sort_rounded, size: 18),
                  label: Text(_sort == SupplierSort.name ? 'A–Z' : 'Amount'),
                  tooltip: 'Sort',
                  onPressed: () => setState(
                    () => _sort = _sort == SupplierSort.name ? SupplierSort.payableDesc : SupplierSort.name,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(suppliersProvider(widget.companyId).future),
              child: switch (suppliers) {
                AsyncValue(:final value?) => _list(context, value),
                AsyncValue(:final error?) => _fill(
                  ErrorState(error: error, onRetry: () => ref.invalidate(suppliersProvider(widget.companyId))),
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

  Widget _list(BuildContext context, List<Supplier> all) {
    if (all.isEmpty) {
      return _fill(
        const EmptyState(
          icon: Icons.local_shipping_outlined,
          title: 'No suppliers yet',
          message: 'Suppliers appear here after the WholeFlow sync service reads them from Tally.',
        ),
      );
    }
    final shown = filterSuppliers(all, query: _query, filter: _filter, sort: _sort);
    if (shown.isEmpty) {
      return _fill(
        EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No suppliers match',
          message: 'Try a different search or clear the filters.',
          action: OutlinedButton(
            onPressed: () {
              _search.clear();
              setState(() {
                _query = '';
                _filter = PayableFilter.all;
              });
            },
            child: const Text('Clear filters'),
          ),
        ),
      );
    }
    final owed = totalOwed(shown);
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: shown.length + 1,
      separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(height: 1, indent: Insets.l),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(Insets.l, Insets.m, Insets.l, Insets.xs),
            child: Text(
              [
                shown.length == all.length ? plural(all.length, 'supplier') : '${shown.length} of ${plural(all.length, 'supplier')}',
                if (owed.isPositive) 'You owe ${formatInrCompact(owed)}',
              ].join(' · '),
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          );
        }
        return SupplierTile(supplier: shown[i - 1]);
      },
    );
  }
}

class SupplierTile extends StatelessWidget {
  const SupplierTile({super.key, required this.supplier});

  final Supplier supplier;

  @override
  Widget build(BuildContext context) {
    final s = supplier;
    final phones = s.allPhones;
    final subtitle = [
      if (phones.isNotEmpty) phones.first,
      if (s.gstin?.trim().isNotEmpty ?? false) s.gstin!.trim(),
    ].join(' · ');
    return ListTile(
      title: Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.42),
        child: PayableText(s.payable, textAlign: TextAlign.end),
      ),
      onTap: () {
        dismissKeyboard();
        context.push('/suppliers/${s.id}');
      },
    );
  }
}
