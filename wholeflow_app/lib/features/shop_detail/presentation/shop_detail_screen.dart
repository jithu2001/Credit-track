import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/balance_text.dart';
import '../../../core/widgets/phone_tile.dart';
import '../../../core/widgets/states.dart';
import '../../analytics/presentation/shop_payments_screen.dart';
import '../../auth/presentation/session_controller.dart';
import '../../company/presentation/company_providers.dart';
import '../../shops/domain/shop.dart';
import 'shop_detail_providers.dart';
import 'statement_view.dart';

class ShopDetailScreen extends ConsumerWidget {
  const ShopDetailScreen({super.key, required this.shopId});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(shopDetailProvider(shopId));
    return switch (detail) {
      AsyncValue(:final value?) => _Loaded(shop: value),
      AsyncValue(:final error?) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(error: error, onRetry: () => ref.invalidate(shopDetailProvider(shopId))),
      ),
      _ => Scaffold(appBar: AppBar(), body: const SkeletonList()),
    };
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.shop});

  final ShopDetail shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showStatement = ref.watch(canViewTransactionsProvider(shop.companyId));
    // How this shop pays (habit, unpaid and paid bills): owners only, like the rest of payment insights.
    final showPayments = showStatement && (ref.watch(currentUserProvider)?.isOwner ?? false);
    final title = Text(shop.name, maxLines: 1, overflow: TextOverflow.ellipsis);
    Future<void> refresh() async {
      ref.invalidate(shopDetailProvider(shop.id));
      ref.invalidate(shopStatementProvider(shop.id));
      await ref.read(shopDetailProvider(shop.id).future);
    }

    final details = RefreshIndicator(
      onRefresh: refresh,
      child: _DetailsTab(shop: shop),
    );
    if (!showStatement) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: details,
      );
    }
    return DefaultTabController(
      length: showPayments ? 3 : 2,
      child: Scaffold(
        appBar: AppBar(
          title: title,
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Details'),
              const Tab(text: 'Statement'),
              if (showPayments) const Tab(text: 'Payments'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            details,
            StatementView(shop: shop),
            if (showPayments) ShopPaymentsView(shopId: shop.id),
          ],
        ),
      ),
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({required this.shop});

  final ShopDetail shop;

  @override
  Widget build(BuildContext context) {
    final phones = shop.allPhones;
    final address = shop.fullAddress;
    return ContentWidth(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Insets.l),
        children: [
          _BalanceCard(shop: shop),
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
                for (final p in phones) PhoneTile(phone: p, fromAddress: shop.phoneSource == 'address' && p == shop.phone),
                if (shop.contactPerson?.trim().isNotEmpty ?? false)
                  ListTile(leading: const Icon(Icons.person_outline), title: Text(shop.contactPerson!.trim())),
                if (shop.email?.trim().isNotEmpty ?? false)
                  ListTile(leading: const Icon(Icons.email_outlined), title: Text(shop.email!.trim())),
                if (address != null)
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(address),
                    subtitle: Text(areaLabel(shop.area)),
                  ),
                if (shop.gstin?.trim().isNotEmpty ?? false)
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(shop.gstin!.trim()),
                    subtitle: const Text('GSTIN'),
                    trailing: IconButton(
                      tooltip: 'Copy GSTIN',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: shop.gstin!.trim()));
                        showMessage(context, 'GSTIN copied');
                      },
                    ),
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

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.shop});

  final ShopDetail shop;

  @override
  Widget build(BuildContext context) {
    final side = shop.receivable.side;
    final caption = switch (side) {
      BalanceSide.dr => 'Owes you',
      BalanceSide.cr => 'In credit (advance)',
      null => 'Nothing due',
    };
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Insets.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(caption, style: context.text.labelLarge),
            const SizedBox(height: Insets.xs),
            BalanceText(shop.receivable, style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: Insets.m),
            Wrap(
              spacing: Insets.l,
              runSpacing: Insets.xs,
              children: [
                Text('Opening balance: ${formatBalance(shop.openingBalance)}', style: context.text.bodySmall),
                if (shop.syncedAt != null) Text('Synced ${timeAgo(shop.syncedAt!)}', style: context.text.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
