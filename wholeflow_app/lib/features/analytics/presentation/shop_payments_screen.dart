import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../domain/payment_analysis.dart';
import 'analytics_providers.dart';
import 'analytics_widgets.dart';

/// One shop's bills under FIFO: what is still open, and how each paid bill was paid.
class ShopPaymentsScreen extends ConsumerWidget {
  const ShopPaymentsScreen({super.key, required this.shopId});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(shopPaymentsProvider(shopId)).value?.profile;
    return Scaffold(
      appBar: AppBar(
        title: Text(profile?.shop.name ?? 'Payments', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Open shop',
            icon: const Icon(Icons.storefront_outlined),
            onPressed: () => context.push('/shop/$shopId'),
          ),
        ],
      ),
      body: ShopPaymentsView(shopId: shopId),
    );
  }
}

/// The body of [ShopPaymentsScreen]; also the shop screen's Payments tab (owners).
class ShopPaymentsView extends ConsumerWidget {
  const ShopPaymentsView({super.key, required this.shopId});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(shopPaymentsProvider(shopId))) {
      AsyncValue(:final value?) when value.profile.bills.isEmpty && !value.profile.advance.isPositive => const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No bills for this shop',
      ),
      AsyncValue(:final value?) => _Body(payments: value),
      AsyncValue(:final error?) => ErrorState(error: error, onRetry: () => ref.invalidate(shopPaymentsProvider(shopId))),
      _ => const SkeletonList(),
    };
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.payments});

  final ShopPayments payments;

  @override
  Widget build(BuildContext context) {
    final p = payments.profile;
    final creditDays = payments.creditDays;
    final open = p.openBills;
    final paid = p.bills.where((b) => !b.isOpen).toList().reversed.toList();
    final s = context.semantic;
    return ContentWidth(
      child: ListView(
        padding: const EdgeInsets.only(bottom: Insets.xxl),
        children: [
          const Padding(
            padding: EdgeInsets.only(top: Insets.s),
            child: CreditDaysFilter(),
          ),
          Padding(
            padding: const EdgeInsets.all(Insets.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    HabitBadge(habit: p.habit(creditDays)),
                    const Spacer(),
                    if (p.lastPaymentDate != null)
                      Text(
                        'Last paid ${formatInr(p.lastPaymentAmount)} on ${formatDate(p.lastPaymentDate!)}',
                        style: context.text.bodySmall,
                      ),
                  ],
                ),
                const SizedBox(height: Insets.m),
                Row(
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: 'Overdue now',
                        value: formatInr(p.overdue),
                        detail: p.overdue.isPositive
                            ? 'oldest bill ${plural(p.maxDaysOverdue, 'day')} past the limit'
                            : 'nothing past the limit',
                        background: p.overdue.isPositive ? s.owedContainer : null,
                        foreground: p.overdue.isPositive ? s.onOwedContainer : null,
                      ),
                    ),
                    const SizedBox(width: Insets.m),
                    Expanded(
                      child: MetricTile(
                        label: 'Unpaid',
                        value: formatInr(p.openAmount),
                        detail: p.advance.isPositive ? 'advance ${formatInr(p.advance)}' : plural(open.length, 'bill'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.m),
                Text(usuallyPays(p), style: context.text.bodyMedium),
                if (p.paidBillCount > 0)
                  Text(
                    '${p.onTimeCount} of ${plural(p.paidBillCount, 'paid bill')} were paid within ${plural(creditDays, 'day')}.',
                    style: context.text.bodyMedium,
                  ),
                if (!p.reconciled) ...[
                  const SizedBox(height: Insets.m),
                  Text(
                    "These bills don't add up to the Tally balance (${formatBalance(p.shop.receivable)}). The next sync usually fixes this.",
                    style: context.text.bodySmall?.copyWith(color: s.warning),
                  ),
                ],
              ],
            ),
          ),
          if (open.isNotEmpty) ...[
            _Header('Unpaid bills (${open.length})'),
            for (final b in open) _OpenBillTile(bill: b, today: p.today),
          ],
          if (paid.isNotEmpty) ...[
            _Header('Paid bills (${payments.closedBills})'),
            for (final b in paid) _PaidBillTile(bill: b),
            if (payments.closedBills > paid.length)
              Padding(
                padding: const EdgeInsets.all(Insets.l),
                child: Text('Showing the latest 100 paid bills.', style: context.text.bodySmall, textAlign: TextAlign.center),
              ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    color: context.colors.surfaceContainer,
    padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.m),
    child: Text(text, style: context.text.titleSmall),
  );
}

String _billTitle(Bill b) => b.isOpening
    ? 'Opening balance'
    : (b.voucher?.isNotEmpty ?? false)
    ? b.voucher!
    : 'Bill';

class _OpenBillTile extends StatelessWidget {
  const _OpenBillTile({required this.bill, required this.today});

  final Bill bill;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final late = bill.daysOverdue(today);
    final dueIn = bill.due.difference(today).inDays;
    final when = late > 0 ? '${plural(late, 'day')} late' : (dueIn == 0 ? 'Due today' : 'Due in ${plural(dueIn, 'day')}');
    final partPaid = bill.remaining != bill.amount;
    return ListTile(
      title: Text(_billTitle(bill)),
      subtitle: Text(
        '${formatDate(bill.date)} · due ${formatDate(bill.due)}'
        '${partPaid ? '\n${formatInr(bill.amount - bill.remaining)} of ${formatInr(bill.amount)} paid' : ''}',
      ),
      isThreeLine: partPaid,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatInr(bill.remaining), style: context.text.titleSmall),
          Text(
            when,
            style: context.text.bodySmall?.copyWith(
              color: late > 0 ? context.semantic.owed : context.colors.onSurfaceVariant,
              fontWeight: late > 0 ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaidBillTile extends StatelessWidget {
  const _PaidBillTile({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final settled = bill.settledOn!;
    final late = settled.difference(bill.due).inDays;
    final how = bill.paidByReceipt
        ? (late > 0 ? '${plural(late, 'day')} late' : 'On time')
        : bill.allocations.every((a) => a.kind == SettleKind.returned)
        ? 'Cleared by return'
        : 'Cleared by adjustment';
    final color = bill.paidByReceipt && late > 0 ? context.semantic.owed : context.semantic.credit;
    return ListTile(
      title: Text(_billTitle(bill)),
      subtitle: Text(
        '${formatDate(bill.date)} · cleared ${formatDate(settled)} (${plural(settled.difference(bill.date).inDays, 'day')})',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatInr(bill.amount), style: context.text.titleSmall),
          Text(how, style: context.text.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}
