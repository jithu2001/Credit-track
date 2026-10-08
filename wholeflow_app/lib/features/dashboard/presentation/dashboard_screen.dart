import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/format.dart';
import '../../inventory/presentation/inventory_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../company/domain/company.dart';
import '../../company/presentation/company_providers.dart';
import '../../company/presentation/company_switcher.dart';
import '../../../core/errors/app_failure.dart';
import '../../analytics/presentation/analytics_providers.dart';
import '../../auth/presentation/session_controller.dart';
import '../../home/account_button.dart';
import '../../home/refresh.dart';
import '../../shops/presentation/shop_tile.dart';
import '../../visits/presentation/visits_today_card.dart';
import '../../shops/presentation/shop_list_controller.dart';
import 'dashboard_providers.dart';
import 'freshness_banner.dart';

const _autoRefresh = Duration(minutes: 5);

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Refresh every 5 minutes while the dashboard is on screen.
    _timer = Timer.periodic(_autoRefresh, (_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true) && TickerMode.valuesOf(context).enabled) {
        unawaited(refreshCompanyData(ref));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(activeCompanyProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const CompanyTitle(screen: 'Dashboard'),
        actions: const [AccountButton()],
      ),
      body: company == null
          ? const SizedBox.shrink()
          : RefreshIndicator(
              onRefresh: () => refreshCompanyData(ref),
              child: ContentWidth(child: _DashboardBody(company: company)),
            ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.company});

  final Company company;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(companySummaryProvider(company.id));
    final top = ref.watch(topDuesProvider(company.id));
    final showSales = ref.watch(canViewTransactionsProvider(company.id));
    final sales = showSales ? ref.watch(monthSalesProvider(company.id)).value : null;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Insets.l),
      children: [
        FreshnessBanner(company: company),
        const SizedBox(height: Insets.l),
        switch (summary) {
          AsyncValue(:final value?) => _StatGrid(
            tiles: [
              _Stat(
                'Total outstanding',
                formatInrCompact(value.totalOutstanding),
                formatInr(value.totalOutstanding),
                tone: _Tone.owed,
              ),
              if (showSales)
                _Stat(
                  'Sales this month',
                  sales == null ? '—' : formatInrCompact(sales.amount),
                  sales == null
                      ? 'Loading…'
                      : '${formatInr(sales.amount)} · ${plural(sales.bills, 'bill')} in ${DateFormat('MMMM').format(sales.month)}',
                ),
              _Stat('Shops with dues', '${value.shopsWithDues}', 'of ${value.shops} shops'),
              _Stat('Shops', '${value.shops}', 'active in Tally'),
            ],
          ),
          AsyncValue(:final error?) => ErrorState(error: error, onRetry: () => refreshCompanyData(ref)),
          AsyncValue(hasValue: true) => const EmptyState(
            icon: Icons.storefront_outlined,
            title: 'No figures yet',
            message: 'Figures appear after the first sync from Tally.',
          ),
          _ => const _StatGrid(tiles: null),
        },
        if (ref.watch(currentUserProvider)?.isOwner ?? false) ...[
          const SizedBox(height: Insets.m),
          _OverdueCard(companyId: company.id),
          StockAlertCard(companyId: company.id),
          VisitsTodayCard(companyId: company.id),
        ],
        const SizedBox(height: Insets.xl),
        Row(
          children: [
            Expanded(child: Text('Top dues', style: context.text.titleMedium)),
            TextButton(
              onPressed: () {
                ref.read(shopsViewControllerProvider.notifier).set(ShopsView.dues);
                context.go('/shops');
              },
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: Insets.s),
        Card.outlined(
          child: switch (top) {
            AsyncValue(:final value?) when value.isEmpty => const Padding(
              padding: EdgeInsets.all(Insets.xl),
              child: Text('No shop owes anything right now.', textAlign: TextAlign.center),
            ),
            AsyncValue(:final value?) => Column(
              children: [
                for (final (i, shop) in value.indexed) ...[if (i > 0) const Divider(height: 1), ShopTile(shop: shop)],
              ],
            ),
            AsyncValue(:final error?) => Padding(
              padding: const EdgeInsets.all(Insets.l),
              child: ErrorState(error: error, onRetry: () => ref.invalidate(topDuesProvider(company.id))),
            ),
            _ => const Column(children: [SkeletonTile(), SkeletonTile(), SkeletonTile()]),
          },
        ),
      ],
    );
  }
}

/// Owner-only: overdue under the current credit period, linking to Payment insights.
class _OverdueCard extends ConsumerWidget {
  const _OverdueCard({required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(paymentSummaryProvider(companyId));
    final s = context.semantic;
    final value = summary.value;
    final overdue = value != null && value.overdue.isPositive;
    final (bg, fg) = overdue
        ? (s.warningContainer, s.onWarningContainer)
        : (context.colors.surfaceContainerHigh, context.colors.onSurface);
    return Card.filled(
      color: bg,
      child: InkWell(
        onTap: () => context.push('/insights'),
        child: Padding(
          padding: const EdgeInsets.all(Insets.l),
          child: Row(
            children: [
              Icon(overdue ? Icons.schedule_rounded : Icons.verified_outlined, color: fg),
              const SizedBox(width: Insets.m),
              Expanded(
                child: switch (summary) {
                  AsyncValue(value: final v?) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.overdue.isPositive ? '${formatInr(v.overdue)} overdue' : 'Nothing overdue',
                        style: context.text.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${plural(v.overdueShops, 'shop')} with bills older than ${plural(v.creditDays, 'day')}',
                        style: context.text.bodySmall?.copyWith(color: fg),
                      ),
                    ],
                  ),
                  AsyncValue(:final error?) => Text(
                    AppFailure.from(error).message,
                    style: context.text.bodySmall?.copyWith(color: fg),
                  ),
                  _ => const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 160, height: 18),
                      SizedBox(height: Insets.xs),
                      SkeletonBox(width: 220, height: 12),
                    ],
                  ),
                },
              ),
              Icon(Icons.chevron_right_rounded, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Owner: items at or below their minimum stock, opening the Stock tab on the
/// low-stock filter. Hidden until some item has a minimum.
class StockAlertCard extends ConsumerWidget {
  const StockAlertCard({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(stockListProvider(companyId)).value;
    if (stock == null || !stock.items.any((i) => i.hasMinimum)) return const SizedBox.shrink();
    final alerts = stock.alerts;
    final s = context.semantic;
    final (bg, fg) = alerts.isEmpty
        ? (context.colors.surfaceContainerHigh, context.colors.onSurface)
        : (s.warningContainer, s.onWarningContainer);
    return Padding(
      padding: const EdgeInsets.only(top: Insets.s),
      child: Card.filled(
        key: const Key('stock-alert'),
        color: bg,
        child: InkWell(
          onTap: () {
            ref.read(inventoryStatusFilterProvider.notifier).set(null);
            ref.read(inventoryBelowMinimumProvider.notifier).set(alerts.isNotEmpty);
            context.go('/stock');
          },
          child: Padding(
            padding: const EdgeInsets.all(Insets.l),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(alerts.isEmpty ? Icons.inventory_2_outlined : Icons.production_quantity_limits_rounded, color: fg),
                const SizedBox(width: Insets.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alerts.isEmpty ? 'Stock above minimum' : '${plural(alerts.length, 'item')} at or below minimum',
                        style: context.text.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
                      ),
                      if (alerts.isEmpty)
                        Text('Every item with a minimum has enough stock', style: context.text.bodySmall?.copyWith(color: fg))
                      else
                        for (final i in alerts.take(3))
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            // Long Tally names give way; the quantities always show.
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    i.name,
                                    style: context.text.bodySmall?.copyWith(color: fg),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: Insets.s),
                                Text(
                                  '${formatQty(i.closingQty, i.unit)} of ${formatQty(i.effectiveMin, i.unit)}',
                                  style: context.text.bodySmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                      if (alerts.length > 3)
                        Text('and ${alerts.length - 3} more', style: context.text.bodySmall?.copyWith(color: fg)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _Tone { neutral, owed }

class _Stat {
  const _Stat(this.label, this.value, this.detail, {this.tone = _Tone.neutral});

  final String label;
  final String value;
  final String detail;
  final _Tone tone;
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles});

  /// Null while loading.
  final List<_Stat>? tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Four tiles: 2×2 on phones, one row on tablets. Three tiles (staff
        // without transactions): the first spans the phone width.
        final count = tiles?.length ?? 4;
        final full = constraints.maxWidth;
        final columns = full >= 720 ? count : 2;
        final cell = (full - Insets.m * (columns - 1)) / columns;
        return Wrap(
          spacing: Insets.m,
          runSpacing: Insets.m,
          children: [
            for (var i = 0; i < count; i++)
              SizedBox(
                width: columns == 2 && count.isOdd && i == 0 ? full : cell,
                child: tiles == null ? const _StatCardSkeleton() : _StatCard(tiles![i]),
              ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.stat);

  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final (bg, fg) = switch (stat.tone) {
      _Tone.owed => (semantic.owedContainer, semantic.onOwedContainer),
      _Tone.neutral => (context.colors.surfaceContainerHigh, context.colors.onSurface),
    };
    return Semantics(
      container: true,
      label: '${stat.label}: ${stat.detail.startsWith('₹') ? stat.detail : '${stat.value}, ${stat.detail}'}',
      excludeSemantics: true,
      child: Card.filled(
        color: bg,
        child: Padding(
          padding: const EdgeInsets.all(Insets.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(stat.label, style: context.text.labelLarge?.copyWith(color: fg)),
              const SizedBox(height: Insets.s),
              Text(
                stat.value,
                style: context.text.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Insets.xs),
              Text(stat.detail, style: context.text.bodySmall?.copyWith(color: fg), maxLines: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCardSkeleton extends StatelessWidget {
  const _StatCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Card.filled(
      child: Padding(
        padding: EdgeInsets.all(Insets.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 100, height: 14),
            SizedBox(height: Insets.m),
            SkeletonBox(width: 80, height: 24),
            SizedBox(height: Insets.s),
            SkeletonBox(width: 120, height: 12),
          ],
        ),
      ),
    );
  }
}
