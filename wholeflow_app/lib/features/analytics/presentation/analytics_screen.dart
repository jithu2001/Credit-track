import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../company/presentation/company_providers.dart';
import '../../company/presentation/company_switcher.dart';
import '../../home/account_button.dart';
import '../domain/payment_analysis.dart';
import 'analytics_providers.dart';
import 'analytics_widgets.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  bool _overdueOnly = true;

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(activeCompanyProvider).value;
    final summary = company == null ? null : ref.watch(paymentSummaryProvider(company.id));
    return Scaffold(
      appBar: AppBar(
        title: const CompanyTitle(screen: 'Analytics'),
        actions: const [AccountButton()],
      ),
      body: company == null
          ? const SizedBox.shrink()
          : RefreshIndicator(
              onRefresh: () => ref.refresh(analyticsDataProvider(company.id).future),
              child: ContentWidth(
                child: switch (summary!) {
                  AsyncValue(:final value?) => _Body(
                    summary: value,
                    overdueOnly: _overdueOnly,
                    onOverdueOnly: (v) => setState(() => _overdueOnly = v),
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
  const _Body({required this.summary, required this.overdueOnly, required this.onOverdueOnly});

  final BusinessPaymentSummary summary;
  final bool overdueOnly;
  final ValueChanged<bool> onOverdueOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(analyticsSortControllerProvider);
    final shown = sortProfiles(overdueOnly ? summary.shops.where((p) => p.overdue.isPositive).toList() : summary.shops, sort);
    final s = context.semantic;
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
            child: Text(
              'Each payment clears the oldest unpaid bill first. A bill is late after ${plural(summary.creditDays, 'day')}.',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(Insets.l),
          sliver: SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, c) {
                final columns = c.maxWidth >= 720 ? 3 : 2;
                final w = (c.maxWidth - Insets.m * (columns - 1)) / columns;
                return Wrap(
                  spacing: Insets.m,
                  runSpacing: Insets.m,
                  children: [
                    SizedBox(
                      width: columns == 2 ? c.maxWidth : w,
                      child: MetricTile(
                        label: 'Overdue',
                        value: formatInr(summary.overdue),
                        detail:
                            '${plural(summary.overdueShops, 'shop')} past ${plural(summary.creditDays, 'day')} · '
                            'of ${formatInr(summary.openAmount)} unpaid',
                        background: s.owedContainer,
                        foreground: s.onOwedContainer,
                      ),
                    ),
                    SizedBox(
                      width: w,
                      child: MetricTile(label: 'Paid on time', value: formatPercent(summary.onTimeRate), detail: 'of paid bills'),
                    ),
                    SizedBox(
                      width: w,
                      child: MetricTile(
                        label: 'Average to pay',
                        value: formatDays(summary.avgDaysToPay),
                        detail: 'from bill date',
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.l),
          sliver: SliverToBoxAdapter(
            child: Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(Insets.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Unpaid bills by age', style: context.text.titleMedium),
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
                Expanded(child: Text('Shops', style: context.text.titleMedium)),
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
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.l),
          sliver: SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: Text('Overdue only (${summary.overdueShops})'),
                selected: overdueOnly,
                onSelected: onOverdueOnly,
              ),
            ),
          ),
        ),
        if (shown.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: Insets.xl),
              child: EmptyState(
                icon: Icons.verified_outlined,
                title: overdueOnly ? 'No shop is overdue' : 'No bills yet',
                message: overdueOnly ? 'Every unpaid bill is within ${plural(summary.creditDays, 'day')}.' : null,
              ),
            ),
          )
        else
          SliverList.separated(
            itemCount: shown.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: Insets.l),
            itemBuilder: (context, i) => _ShopRow(profile: shown[i]),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: Insets.xxl)),
      ],
    );
  }
}

class _ShopRow extends StatelessWidget {
  const _ShopRow({required this.profile});

  final ShopPaymentProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    final overdueText = p.overdue.isPositive
        ? '${formatInr(p.overdue)} overdue · oldest ${plural(p.maxDaysOverdue, 'day')} late'
        : (p.openAmount.isPositive ? 'Nothing overdue · ${formatInr(p.openAmount)} not yet due' : 'Nothing unpaid');
    return InkWell(
      onTap: () => context.push('/analytics/shop/${p.shop.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
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
                      StatusBadge(status: p.status),
                      Text(areaLabel(p.shop.area), style: muted),
                    ],
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(overdueText, style: context.text.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: Insets.m),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatPercent(p.onTimeRate), style: context.text.titleSmall),
                Text('on time', style: muted),
                const SizedBox(height: Insets.xs),
                Text(formatDays(p.avgDaysToPay), style: context.text.titleSmall),
                Text('avg to pay', style: muted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
