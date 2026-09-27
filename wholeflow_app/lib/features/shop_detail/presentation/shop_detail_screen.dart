import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/phone.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/balance_text.dart';
import '../../../core/widgets/states.dart';
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
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: title,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Details'),
              Tab(text: 'Statement'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            details,
            StatementView(shop: shop),
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
                for (final p in phones) _PhoneTile(phone: p, fromAddress: shop.phoneSource == 'address' && p == shop.phone),
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

class _PhoneTile extends StatelessWidget {
  const _PhoneTile({required this.phone, required this.fromAddress});

  final String phone;
  final bool fromAddress;

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showMessage(context, "Couldn't open ${uri.scheme == 'tel' ? 'the dialer' : 'WhatsApp'}.");
  }

  @override
  Widget build(BuildContext context) {
    final wa = whatsAppUri(phone);
    return ListTile(
      leading: const Icon(Icons.phone_outlined),
      title: Text(phone),
      subtitle: fromAddress ? const Text('Found in address') : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Call $phone',
            icon: const Icon(Icons.call_rounded),
            onPressed: () => _open(context, telUri(phone)),
          ),
          if (wa != null)
            IconButton(tooltip: 'WhatsApp $phone', icon: const Icon(Icons.chat_rounded), onPressed: () => _open(context, wa)),
        ],
      ),
    );
  }
}
