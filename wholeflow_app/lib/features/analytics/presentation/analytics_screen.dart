import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../company/presentation/company_providers.dart';
import '../../shops/presentation/shop_list_controller.dart';
import '../domain/payment_analysis.dart';
import 'analytics_providers.dart';
import 'analytics_widgets.dart';

/// Which shops the list shows, by payment habit.
enum HabitFilter {
  all('All'),
  late('Pay late'),
  onTime('Pay on time'),
  noPayments('No payments');

  const HabitFilter(this.label);
  final String label;

  bool matches(PayHabit h) => switch (this) {
    all => true,
    late => h == PayHabit.late || h == PayHabit.veryLate,
    onTime => h == PayHabit.onTime,
    noPayments => h == PayHabit.noPayments,
  };
}

/// Owner-only, opened from the Dashboard overdue card: how much is overdue and
/// whether it is improving, how shops pay in general, and each shop's habit.
/// Chasing today's dues happens in Shops → Overdue, which this screen links to.
class PaymentInsightsScreen extends ConsumerStatefulWidget {
  const PaymentInsightsScreen({super.key});

  @override
  ConsumerState<PaymentInsightsScreen> createState() => _PaymentInsightsScreenState();
}

class _PaymentInsightsScreenState extends ConsumerState<PaymentInsightsScreen> {
  HabitFilter _filter = HabitFilter.all;

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(activeCompanyProvider).value;
    final summary = company == null ? null : ref.watch(paymentSummaryProvider(company.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Payment insights')),
      body: company == null
          ? const SizedBox.shrink()
          : RefreshIndicator(
              onRefresh: () => ref.refresh(analyticsDataProvider(company.id).future),
              child: ContentWidth(
                child: switch (summary!) {
                  AsyncValue(:final value?) => _Body(
                    companyId: company.id,
                    summary: value,
                    filter: _filter,
                    onFilter: (v) => setState(() => _filter = v),
                  ),
                  AsyncValue(:final error?) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: Insets.xxl),
                      ErrorState(error: error, onRetry: () => ref.invalidate(analyticsDataProvider(company.id))),
                    ],
                  ),
                  _ => const SkeletonList(),
                },
              ),
            ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.companyId, required this.summary, required this.filter, required this.onFilter});

  final String companyId;
  final BusinessPaymentSummary summary;
  final HabitFilter filter;
  final ValueChanged<HabitFilter> onFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(analyticsSortControllerProvider);
    final days = summary.creditDays;
    final counts = {for (final f in HabitFilter.values) f: summary.shops.where((p) => f.matches(p.habit(days))).length};
    final shown = sortProfiles(summary.shops.where((p) => filter.matches(p.habit(days))).toList(), sort);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: Insets.s),
            child: CreditDaysFilter(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, 0),
          sliver: SliverToBoxAdapter(
            child: _OverviewCard(companyId: companyId, summary: summary),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Insets.l, Insets.l, Insets.l, 0),
          sliver: SliverToBoxAdapter(child: _HabitsCard(summary: summary)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Insets.l, Insets.l, Insets.l, 0),
          sliver: SliverToBoxAdapter(
            child: Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(Insets.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Unpaid money, by how late it is', style: context.text.titleMedium),
                    const SizedBox(height: Insets.xs),
                    Text(
                      'A bill is late once it is more than ${plural(days, 'day')} old.',
                      style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: Insets.s),
                    AgeingBars(ageing: summary.ageing),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Insets.l, Insets.xl, Insets.s, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(child: Text('How each shop pays', style: context.text.titleMedium)),
                PopupMenuButton<AnalyticsSort>(
                  tooltip: 'Sort shops',
                  initialValue: sort,
                  onSelected: (v) => ref.read(analyticsSortControllerProvider.notifier).set(v),
                  itemBuilder: (context) => [for (final v in AnalyticsSort.values) PopupMenuItem(value: v, child: Text(v.label))],
                  child: Padding(
                    padding: const EdgeInsets.all(Insets.s),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sort_rounded, size: 20),
                        const SizedBox(width: Insets.xs),
                        Text(sort.label, style: context.text.labelLarge),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.s),
              children: [
                for (final f in HabitFilter.values) ...[
                  ChoiceChip(label: Text('${f.label} (${counts[f]})'), selected: filter == f, onSelected: (_) => onFilter(f)),
                  const SizedBox(width: Insets.s),
                ],
              ],
            ),
          ),
        ),
        if (shown.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: Insets.xl),
              child: EmptyState(
                icon: Icons.storefront_outlined,
                title: summary.shops.isEmpty ? 'No bills yet' : 'No shops here',
                message: summary.shops.isEmpty ? null : 'Try another filter.',
              ),
            ),
          )
        else
          SliverList.separated(
            itemCount: shown.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: Insets.l),
            itemBuilder: (context, i) => _ShopRow(profile: shown[i], creditDays: days),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: Insets.xxl)),
      ],
    );
  }
}

/// "₹10 L is overdue in 87 shops", the change over a month, and the way to
/// the list of whom to call.
class _OverviewCard extends ConsumerWidget {
  const _OverviewCard({required this.companyId, required this.summary});

  final String companyId;
  final BusinessPaymentSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.semantic;
    final overdue = summary.overdue.isPositive;
    final (bg, fg) = overdue ? (s.owedContainer, s.onOwedContainer) : (s.creditContainer, s.onCreditContainer);
    final monthAgo = ref.watch(overdueMonthAgoProvider(companyId)).value;
    return Card.filled(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(Insets.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Overdue now', style: context.text.labelLarge?.copyWith(color: fg)),
            Text(
              overdue ? formatInr(summary.overdue) : 'Nothing',
              style: context.text.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
            Text(
              overdue
                  ? '${plural(summary.overdueShops, 'shop')} with bills older than ${plural(summary.creditDays, 'day')}'
                  : 'No bill is older than ${plural(summary.creditDays, 'day')}',
              style: context.text.bodyMedium?.copyWith(color: fg),
            ),
            if (monthAgo != null) ...[
              const SizedBox(height: Insets.m),
              _TrendLine(now: summary.overdue, monthAgo: monthAgo, color: fg),
            ],
            if (overdue) ...[
              const SizedBox(height: Insets.m),
              FilledButton.icon(
                key: const Key('see-who-to-call'),
                icon: const Icon(Icons.phone_forwarded_outlined),
                label: const Text('See who to call'),
                onPressed: () {
                  ref.read(shopsViewControllerProvider.notifier).set(ShopsView.overdue);
                  context.go('/shops');
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrendLine extends StatelessWidget {
  const _TrendLine({required this.now, required this.monthAgo, required this.color});

  final Money now;
  final Money monthAgo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final diff = now - monthAgo;
    // Within 1% (or ₹100) counts as unchanged.
    final small = diff.abs().paise <= (monthAgo.abs().paise ~/ 100 > 10000 ? monthAgo.abs().paise ~/ 100 : 10000);
    final (icon, text) = small
        ? (Icons.trending_flat_rounded, 'About the same as a month ago (${formatInr(monthAgo)})')
        : diff.isNegative
        ? (Icons.trending_down_rounded, '${formatInr(diff.abs())} less than a month ago — getting better')
        : (Icons.trending_up_rounded, '${formatInr(diff)} more than a month ago — getting worse');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: Insets.s),
        Expanded(
          child: Text(text, style: context.text.bodyMedium?.copyWith(color: color)),
        ),
      ],
    );
  }
}

/// Two plain sentences on how shops pay in general.
class _HabitsCard extends StatelessWidget {
  const _HabitsCard({required this.summary});

  final BusinessPaymentSummary summary;

  @override
  Widget build(BuildContext context) {
    final days = summary.creditDays;
    final rows = [
      if (summary.avgDaysToPay != null)
        (Icons.schedule_rounded, 'Shops usually pay ${formatDays(summary.avgDaysToPay)} after the bill.'),
      if (summary.onTimeRate != null)
        (Icons.check_circle_outline, 'About ${inTen(summary.onTimeRate!)} bills are paid within ${plural(days, 'day')}.'),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(Insets.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How shops pay', style: context.text.titleMedium),
            for (final (icon, text) in rows) ...[
              const SizedBox(height: Insets.m),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: context.colors.onSurfaceVariant),
                  const SizedBox(width: Insets.m),
                  Expanded(child: Text(text, style: context.text.bodyMedium)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShopRow extends StatelessWidget {
  const _ShopRow({required this.profile, required this.creditDays});

  final ShopPaymentProfile profile;
  final int creditDays;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    return InkWell(
      onTap: () => context.push('/analytics/shop/${p.shop.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.shop.name, style: context.text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: Insets.xs),
            Wrap(
              spacing: Insets.s,
              runSpacing: Insets.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                HabitBadge(habit: p.habit(creditDays)),
                Text(areaLabel(p.shop.area), style: muted),
              ],
            ),
            const SizedBox(height: Insets.xs),
            Text(usuallyPays(p), style: context.text.bodySmall),
            if (p.overdue.isPositive)
              Text(
                '${formatInr(p.overdue)} overdue now',
                style: context.text.bodySmall?.copyWith(color: context.semantic.owed, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
    );
  }
}
