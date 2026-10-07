import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../../core/errors/app_failure.dart';
import '../../auth/presentation/session_controller.dart';
import '../../company/presentation/company_providers.dart';
import '../domain/stock_item.dart';
import 'inventory_providers.dart';
import 'stock_widgets.dart';

class StockItemScreen extends ConsumerWidget {
  const StockItemScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(stockItemProvider(itemId));
    return switch (item) {
      AsyncValue(:final value?) => _Loaded(item: value),
      AsyncValue(:final error?) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(error: error, onRetry: () => ref.invalidate(stockItemProvider(itemId))),
      ),
      _ => Scaffold(appBar: AppBar(), body: const SkeletonList()),
    };
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.item});

  final StockItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(currentUserProvider)?.isOwner ?? false;
    Future<void> refresh() async {
      ref
        ..invalidate(stockItemProvider(item.id))
        ..invalidate(itemPurchasesProvider(item.id));
      await ref.read(stockItemProvider(item.id).future);
    }

    return Scaffold(
      appBar: AppBar(title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ContentWidth(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Insets.l),
            children: [
              _QtyCard(item: item),
              const SizedBox(height: Insets.l),
              SectionCard(
                title: 'Item',
                trailing: IconButton(
                  tooltip: 'Copy name',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: item.name));
                    showMessage(context, 'Item name copied');
                  },
                ),
                children: [
                  InfoRow('Name', item.name),
                  if (item.aliases.isNotEmpty)
                    InfoRow(item.aliases.length == 1 ? 'Part no.' : 'Part nos.', item.aliases.join('\n')),
                  InfoRow('Group', groupLabel(item.group)),
                  if (item.unit?.trim().isNotEmpty ?? false) InfoRow('Unit', item.unit!.trim()),
                ],
              ),
              const SizedBox(height: Insets.l),
              _MinimumCard(item: item, isOwner: isOwner),
              if (isOwner) ...[
                const SizedBox(height: Insets.l),
                SectionCard(
                  title: 'Cost',
                  children: [
                    if (item.closingRate != null) InfoRow('Valuation rate', formatRate(item.closingRate!, item.unit)),
                    if (item.closingValue != null) InfoRow('Stock value', formatInr(item.closingValue!)),
                    if (item.lastPurchaseDate != null) ...[
                      InfoRow('Last purchased', formatDate(item.lastPurchaseDate!)),
                      if (item.lastPurchaseRate != null)
                        InfoRow('Last purchase rate', formatRate(item.lastPurchaseRate!, item.unit)),
                      if (item.lastSupplier?.trim().isNotEmpty ?? false) InfoRow('Last supplier', item.lastSupplier!.trim()),
                    ] else
                      const InfoRow('Last purchased', 'No purchase synced'),
                  ],
                ),
                const SizedBox(height: Insets.l),
                _RecentPurchases(item: item),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The item's minimum stock: the owner's own, else Tally's reorder level.
class _MinimumCard extends ConsumerWidget {
  const _MinimumCard({required this.item, required this.isOwner});

  final StockItem item;
  final bool isOwner;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final companyId = ref.read(activeCompanyProvider).value?.id;
    if (companyId == null) return;
    final choice = await askMinimum(
      context,
      title: item.name,
      unit: item.unit,
      current: item.minQty,
      canRemove: item.minQty != null,
    );
    if (choice == null || !context.mounted) return;
    try {
      await setStockMinimum(ref, companyId, [item.id], choice.min);
      if (context.mounted) showMessage(context, choice.min == null ? 'Minimum removed' : 'Minimum saved');
    } on AppFailure catch (f) {
      if (context.mounted) showMessage(context, f.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usingTally = item.minQty == null && item.reorderLevel > 0;
    return SectionCard(
      title: 'Stock alert',
      trailing: isOwner
          ? TextButton(
              key: const Key('edit-minimum'),
              onPressed: () => _edit(context, ref),
              child: Text(item.minQty == null ? 'Set minimum' : 'Change'),
            )
          : null,
      children: [
        InfoRow('Minimum stock', item.minQty == null ? 'Not set' : formatQty(item.minQty!, item.unit)),
        if (item.reorderLevel > 0) InfoRow('Tally reorder level', formatQty(item.reorderLevel, item.unit)),
        InfoRow(
          'Alert when stock is',
          item.hasMinimum ? 'at or below ${formatQty(item.effectiveMin, item.unit)}${usingTally ? ' (Tally)' : ''}' : 'No alert',
          valueStyle: item.atOrBelowMinimum
              ? context.text.bodyMedium?.copyWith(color: context.semantic.warning, fontWeight: FontWeight.w600)
              : null,
        ),
      ],
    );
  }
}

class _QtyCard extends StatelessWidget {
  const _QtyCard({required this.item});

  final StockItem item;

  @override
  Widget build(BuildContext context) {
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Insets.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Closing stock', style: context.text.labelLarge),
            const SizedBox(height: Insets.xs),
            Text(
              formatQty(item.closingQty, item.unit),
              style: context.text.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: Insets.s),
            Wrap(
              spacing: Insets.l,
              runSpacing: Insets.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StockStatusLabel(item.status, style: context.text.labelLarge),
                if (item.syncedAt != null) Text('Synced ${timeAgo(item.syncedAt!)}', style: context.text.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentPurchases extends ConsumerWidget {
  const _RecentPurchases({required this.item});

  final StockItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchases = ref.watch(itemPurchasesProvider(item.id));
    return SectionCard(
      title: 'Recent purchases',
      children: switch (purchases) {
        AsyncValue(:final value?) when value.isEmpty => [
          const ListTile(leading: Icon(Icons.receipt_long_outlined), title: Text('No purchase bills for this item')),
        ],
        AsyncValue(:final value?) => [
          for (final p in value)
            ListTile(
              title: Text(
                p.supplierName.isEmpty ? 'Unknown supplier' : p.supplierName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  formatDate(p.date),
                  if (p.voucherNumber?.isNotEmpty ?? false) '#${p.voucherNumber}',
                  formatQty(p.qty, p.unit ?? item.unit),
                ].join(' · '),
              ),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatInr(p.rate), style: context.text.titleSmall),
                  Text(
                    formatInrCompact(p.amount),
                    style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ],
              ),
              onTap: () => context.push('/purchases/${p.purchaseId}'),
            ),
        ],
        AsyncValue(:final error?) => [ErrorTile(error: error, onRetry: () => ref.invalidate(itemPurchasesProvider(item.id)))],
        _ => const [SkeletonTile(), SkeletonTile()],
      },
    );
  }
}
