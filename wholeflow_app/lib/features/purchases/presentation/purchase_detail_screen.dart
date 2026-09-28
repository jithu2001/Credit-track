import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../inventory/presentation/stock_widgets.dart';
import '../domain/purchase.dart';
import 'purchase_providers.dart';

/// One purchase bill: supplier, item lines, taxes and total (owner only).
class PurchaseDetailScreen extends ConsumerWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(purchaseDetailProvider(purchaseId));
    return switch (detail) {
      AsyncValue(:final value?) => _Loaded(bill: value),
      AsyncValue(:final error?) => Scaffold(
        appBar: AppBar(title: const Text('Purchase bill')),
        body: ErrorState(error: error, onRetry: () => ref.invalidate(purchaseDetailProvider(purchaseId))),
      ),
      _ => Scaffold(appBar: AppBar(title: const Text('Purchase bill')), body: const SkeletonList()),
    };
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.bill});

  final PurchaseDetail bill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = bill.summary;
    final title = s.voucherNumber?.trim().isNotEmpty ?? false ? 'Bill ${s.voucherNumber!.trim()}' : 'Purchase bill';
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(purchaseDetailProvider(s.id));
          await ref.read(purchaseDetailProvider(s.id).future);
        },
        child: ContentWidth(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Insets.l),
            children: [
              _HeaderCard(bill: bill),
              const SizedBox(height: Insets.l),
              SectionCard(
                title: 'Items',
                children: [
                  if (bill.lines.isEmpty) const ListTile(title: Text('No item lines on this bill')),
                  for (final l in bill.lines) _LineTile(line: l),
                ],
              ),
              const SizedBox(height: Insets.l),
              SectionCard(
                title: 'Amount',
                children: [
                  InfoRow('Items (taxable)', formatInr(s.taxable)),
                  for (final e in bill.ledgerEntries)
                    InfoRow(e.ledger.isEmpty ? 'Other' : e.ledger, formatInr(e.amount)),
                  if (bill.ledgerEntries.isEmpty && !bill.taxAndOther.isZero)
                    InfoRow('Tax and other charges', formatInr(bill.taxAndOther)),
                  const Divider(indent: Insets.l, endIndent: Insets.l),
                  InfoRow(
                    'Bill total',
                    formatInr(s.total),
                    valueStyle: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              if (bill.narration?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: Insets.l),
                SectionCard(
                  title: 'Narration',
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.xs),
                      child: Text(bill.narration!.trim()),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.bill});

  final PurchaseDetail bill;

  @override
  Widget build(BuildContext context) {
    final s = bill.summary;
    final supplier = Text(
      s.supplierLabel,
      style: context.text.titleLarge,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Insets.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.supplierId == null)
              supplier
            else
              InkWell(
                borderRadius: BorderRadius.circular(Insets.s),
                onTap: () => context.push('/suppliers/${s.supplierId}'),
                child: Row(
                  children: [
                    Flexible(child: supplier),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            const SizedBox(height: Insets.xs),
            Text(
              formatInr(s.total),
              style: context.text.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: Insets.m),
            Wrap(
              spacing: Insets.l,
              runSpacing: Insets.xs,
              children: [
                Text(formatDate(s.date), style: context.text.bodySmall),
                if (s.voucherType?.trim().isNotEmpty ?? false) Text(s.voucherType!.trim(), style: context.text.bodySmall),
                if (s.supplierBillNumber?.trim().isNotEmpty ?? false)
                  Text('Supplier bill ${s.supplierBillNumber!.trim()}', style: context.text.bodySmall),
                if (bill.totalQty > 0) Text('Qty ${formatQty(bill.totalQty)}', style: context.text.bodySmall),
                if (bill.syncedAt != null) Text('Synced ${timeAgo(bill.syncedAt!)}', style: context.text.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line});

  final PurchaseLine line;

  @override
  Widget build(BuildContext context) {
    final details = [
      '${formatQty(line.qty, line.unit)} × ${formatInr(line.rate)}',
      if (line.discountPercent > 0) '${formatQty(line.discountPercent)}% off',
      if (line.godown?.trim().isNotEmpty ?? false) line.godown!.trim(),
    ].join(' · ');
    return ListTile(
      title: Text(line.itemName, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(details),
      trailing: Text(
        formatInr(line.amount),
        style: context.text.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
      onTap: line.stockItemId == null ? null : () => context.push('/stock/item/${line.stockItemId}'),
    );
  }
}
