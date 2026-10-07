import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../domain/purchase.dart';
import 'purchase_providers.dart';

final _monthFormat = DateFormat('MMMM yyyy');

String formatMonth(DateTime month) => _monthFormat.format(month);

/// Purchase bills, newest first, grouped under month headings. Used by the
/// Purchases tab (whole company, with search and month totals) and by a
/// supplier's Bills tab ([supplierId] set).
class PurchaseListView extends ConsumerStatefulWidget {
  const PurchaseListView({super.key, required this.companyId, this.supplierId, this.showSupplier = true});

  final String companyId;
  final String? supplierId;

  /// Off on a supplier's own list, where every bill has the same supplier.
  final bool showSupplier;

  @override
  ConsumerState<PurchaseListView> createState() => _PurchaseListViewState();
}

class _PurchaseListViewState extends ConsumerState<PurchaseListView> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  PurchaseQuery get _key => (companyId: widget.companyId, search: _query, supplierId: widget.supplierId);

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(purchaseListProvider(_key))
      ..invalidate(recentMonthsProvider(widget.companyId));
    try {
      await ref.read(purchaseListProvider(_key).future);
    } catch (_) {
      // The list shows its own error.
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final list = ref.watch(purchaseListProvider(_key));
    final wholeCompany = widget.supplierId == null;
    return ContentWidth(
      child: Column(
        children: [
          if (wholeCompany)
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, Insets.s),
              child: SearchBar(
                controller: _search,
                hintText: 'Search supplier or bill no.',
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
          if (wholeCompany) const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: switch (list) {
                AsyncValue(:final value?) => _list(context, value, wholeCompany),
                AsyncValue(:final error?) => _fill(
                  ErrorState(error: error, onRetry: () => ref.invalidate(purchaseListProvider(_key))),
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

  Widget _list(BuildContext context, PurchasePage page, bool wholeCompany) {
    if (page.items.isEmpty) {
      return _fill(
        _query.isNotEmpty
            ? const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No bills match',
                message: 'Try a supplier name, voucher number or the supplier bill number.',
              )
            : const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No purchase bills yet',
                message: 'Purchase bills appear here after the WholeFlow sync service reads them from Tally.',
              ),
      );
    }
    // Month headings between bills; the header row (month totals) comes first.
    final rows = <Object>[];
    DateTime? month;
    for (final p in page.items) {
      final m = DateTime(p.date.year, p.date.month);
      if (m != month) rows.add(m);
      month = m;
      rows.add(p);
    }
    final footer = page.hasMore || page.loadMoreError != null;
    final showTotals = wholeCompany && _query.isEmpty;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 600) ref.read(purchaseListProvider(_key).notifier).loadMore();
        return false;
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: (showTotals ? 1 : 0) + rows.length + (footer ? 1 : 0),
        itemBuilder: (context, i) {
          if (showTotals) {
            if (i == 0) return _RecentMonths(companyId: widget.companyId);
            i -= 1;
          }
          if (i < rows.length) {
            final row = rows[i];
            if (row is DateTime) return _MonthHeading(month: row);
            return PurchaseTile(purchase: row as PurchaseSummary, showSupplier: widget.showSupplier);
          }
          if (page.loadMoreError != null) {
            return Padding(
              padding: const EdgeInsets.all(Insets.l),
              child: Column(
                children: [
                  Text(page.loadMoreError!.message, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => ref.read(purchaseListProvider(_key).notifier).loadMore(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          return const SkeletonTile();
        },
      ),
    );
  }
}

class _MonthHeading extends StatelessWidget {
  const _MonthHeading({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.l, Insets.l, Insets.l, Insets.xs),
      child: Text(formatMonth(month), style: context.text.titleSmall?.copyWith(color: context.colors.primary)),
    );
  }
}

/// This month and last month, side by side.
class _RecentMonths extends ConsumerWidget {
  const _RecentMonths({required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final months = ref.watch(recentMonthsProvider(companyId)).value;
    if (months == null) return const SizedBox.shrink();
    final now = DateTime.now();
    MonthPurchases of(DateTime m) =>
        months.firstWhere((x) => x.month == m, orElse: () => MonthPurchases(month: m, bills: 0, total: Money.zero));
    final cards = [
      (label: 'This month', data: of(monthStart(now))),
      (label: 'Last month', data: of(monthStart(now, monthsBack: 1))),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.l, Insets.m, Insets.l, 0),
      child: Row(
        children: [
          for (final (i, c) in cards.indexed) ...[
            if (i > 0) const SizedBox(width: Insets.m),
            Expanded(
              child: Card.filled(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(Insets.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.label, style: context.text.labelMedium),
                      const SizedBox(height: Insets.xs),
                      Text(
                        formatInrCompact(c.data.total),
                        style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                      ),
                      Text(
                        plural(c.data.bills, 'bill'),
                        style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PurchaseTile extends StatelessWidget {
  const PurchaseTile({super.key, required this.purchase, this.showSupplier = true});

  final PurchaseSummary purchase;
  final bool showSupplier;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    final number = p.supplierBillNumber?.trim().isNotEmpty ?? false ? p.supplierBillNumber!.trim() : p.voucherNumber?.trim();
    final details = [
      formatDate(p.date),
      if (number != null && number.isNotEmpty) 'Bill $number',
      plural(p.lineCount, 'item'),
    ].join(' · ');
    return ListTile(
      title: Text(showSupplier ? p.supplierLabel : details, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: showSupplier ? Text(details, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
      trailing: Text(
        formatInr(p.total),
        style: context.text.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
      onTap: () {
        dismissKeyboard();
        context.push('/purchases/${p.id}');
      },
    );
  }
}
