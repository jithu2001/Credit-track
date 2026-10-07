import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/phone_tile.dart';
import '../../../core/widgets/states.dart';
import '../../inventory/presentation/stock_widgets.dart';
import '../../purchases/presentation/purchase_list_view.dart';
import '../../purchases/presentation/purchase_providers.dart';
import '../domain/supplier.dart';
import 'payable_text.dart';
import 'supplier_providers.dart';

/// A supplier's balance and contact (Details) and their purchase bills (Bills).
class SupplierDetailScreen extends ConsumerWidget {
  const SupplierDetailScreen({super.key, required this.supplierId});

  final String supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(supplierDetailProvider(supplierId));
    return switch (detail) {
      AsyncValue(:final value?) => _Loaded(supplier: value),
      AsyncValue(:final error?) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(error: error, onRetry: () => ref.invalidate(supplierDetailProvider(supplierId))),
      ),
      _ => Scaffold(appBar: AppBar(), body: const SkeletonList()),
    };
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.supplier});

  final Supplier supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = supplier;
    final monthsKey = (companyId: s.companyId, supplierId: s.id);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Details'),
              Tab(text: 'Bills'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                ref
                  ..invalidate(supplierDetailProvider(s.id))
                  ..invalidate(supplierMonthsProvider(monthsKey));
                await ref.read(supplierDetailProvider(s.id).future);
              },
              child: _DetailsTab(supplier: s),
            ),
            PurchaseListView(companyId: s.companyId, supplierId: s.id, showSupplier: false),
          ],
        ),
      ),
    );
  }
}

class _DetailsTab extends ConsumerWidget {
  const _DetailsTab({required this.supplier});

  final Supplier supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = supplier;
    final phones = s.allPhones;
    final address = s.fullAddress;
    return ContentWidth(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Insets.l),
        children: [
          _PayableCard(supplier: s),
          const SizedBox(height: Insets.l),
          _PurchasedCard(supplier: s),
          const SizedBox(height: Insets.l),
          Card.outlined(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Insets.l, Insets.l, Insets.l, Insets.xs),
                  child: Text('Contact', style: context.text.titleMedium),
                ),
                if (phones.isEmpty)
                  const ListTile(leading: Icon(Icons.phone_disabled_outlined), title: Text('No phone number in Tally')),
                for (final p in phones) PhoneTile(phone: p),
                if (s.contactPerson?.trim().isNotEmpty ?? false)
                  ListTile(leading: const Icon(Icons.person_outline), title: Text(s.contactPerson!.trim())),
                if (s.email?.trim().isNotEmpty ?? false)
                  ListTile(leading: const Icon(Icons.email_outlined), title: Text(s.email!.trim())),
                if (address != null) ListTile(leading: const Icon(Icons.location_on_outlined), title: Text(address)),
                if (s.gstin?.trim().isNotEmpty ?? false)
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(s.gstin!.trim()),
                    subtitle: const Text('GSTIN'),
                    trailing: IconButton(
                      tooltip: 'Copy GSTIN',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: s.gstin!.trim()));
                        showMessage(context, 'GSTIN copied');
                      },
                    ),
                  ),
                if (s.ledgerGroup?.trim().isNotEmpty ?? false)
                  ListTile(
                    leading: const Icon(Icons.account_tree_outlined),
                    title: Text(s.ledgerGroup!.trim()),
                    subtitle: const Text('Tally group'),
                  ),
                const SizedBox(height: Insets.s),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PayableCard extends StatelessWidget {
  const _PayableCard({required this.supplier});

  final Supplier supplier;

  @override
  Widget build(BuildContext context) {
    final p = supplier.payable;
    final caption = p.isPositive
        ? 'You owe'
        : p.isNegative
        ? 'Advance paid'
        : 'Nothing due';
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Insets.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(caption, style: context.text.labelLarge),
            const SizedBox(height: Insets.xs),
            PayableText(p, style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: Insets.m),
            Wrap(
              spacing: Insets.l,
              runSpacing: Insets.xs,
              children: [
                Text('Opening balance: ${_side(supplier.openingPayable)}', style: context.text.bodySmall),
                if (supplier.syncedAt != null) Text('Synced ${timeAgo(supplier.syncedAt!)}', style: context.text.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Payable-signed amount in Tally terms: owed = Cr, advance = Dr.
  static String _side(Money m) =>
      m.isZero ? formatInr(m) : '${formatInr(m.abs())} ${m.isPositive ? 'Cr' : 'Dr'}';
}

/// Purchases from this supplier over the last 12 months.
class _PurchasedCard extends ConsumerWidget {
  const _PurchasedCard({required this.supplier});

  final Supplier supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final months = ref.watch(supplierMonthsProvider((companyId: supplier.companyId, supplierId: supplier.id)));
    return SectionCard(
      title: 'Purchases, last 12 months',
      children: switch (months) {
        AsyncValue(:final value?) => [
          InfoRow('Total', formatInr(value.fold(Money.zero, (sum, m) => sum + m.total))),
          InfoRow('Bills', '${value.fold(0, (sum, m) => sum + m.bills)}'),
          if (value.isNotEmpty) InfoRow('Last month with a bill', formatMonth(value.first.month)),
        ],
        AsyncValue(:final error?) => [
          ErrorTile(
            error: error,
            onRetry: () => ref.invalidate(supplierMonthsProvider((companyId: supplier.companyId, supplierId: supplier.id))),
          ),
        ],
        _ => const [SkeletonTile()],
      },
    );
  }
}
