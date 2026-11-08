import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/states.dart';
import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/business_trend.dart';
import 'dashboard_providers.dart';

/// Owner: sales, collections or purchases month by month (6 or 12 months),
/// with the picked month's figure, its change and the period's totals.
class BusinessTrendCard extends ConsumerStatefulWidget {
  const BusinessTrendCard({super.key, required this.companyId});

  final String companyId;

  @override
  ConsumerState<BusinessTrendCard> createState() => _BusinessTrendCardState();
}

class _BusinessTrendCardState extends ConsumerState<BusinessTrendCard> {
  TrendMetric _metric = TrendMetric.sales;

  /// Picked bar; null = the current month (the last one).
  int? _picked;

  @override
  Widget build(BuildContext context) {
    final months = ref.watch(trendMonthsProvider);
    final trend = ref.watch(businessTrendProvider(widget.companyId));
    return Card.outlined(
      key: const Key('business-trend'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Insets.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Monthly trend', style: context.text.titleMedium)),
                SegmentedButton<int>(
                  key: const Key('trend-months'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: 6, label: Text('6 mo')),
                    ButtonSegment(value: 12, label: Text('12 mo')),
                  ],
                  selected: {months},
                  onSelectionChanged: (s) {
                    setState(() => _picked = null);
                    ref.read(trendMonthsProvider.notifier).set(s.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: Insets.m),
            SegmentedButton<TrendMetric>(
              key: const Key('trend-metric'),
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
              segments: [
                for (final m in TrendMetric.values)
                  ButtonSegment(
                    value: m,
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text(m.label)),
                  ),
              ],
              selected: {_metric},
              onSelectionChanged: (s) => setState(() => _metric = s.first),
            ),
            const SizedBox(height: Insets.m),
            switch (trend) {
              AsyncValue(:final value?) when value.months.isNotEmpty => _Body(
                trend: value,
                metric: _metric,
                picked: (_picked ?? value.months.length - 1).clamp(0, value.months.length - 1),
                onPick: (i) => setState(() => _picked = i),
              ),
              AsyncValue(hasValue: true) => const Padding(
                padding: EdgeInsets.all(Insets.l),
                child: Text('No figures yet.', textAlign: TextAlign.center),
              ),
              AsyncValue(:final error?) => ErrorState(
                error: error,
                onRetry: () => ref.invalidate(businessTrendProvider(widget.companyId)),
              ),
              _ => const SizedBox(height: 220, child: Center(child: CircularProgressIndicator())),
            },
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.trend, required this.metric, required this.picked, required this.onPick});

  final BusinessTrend trend;
  final TrendMetric metric;
  final int picked;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final months = trend.months;
    final m = months[picked];
    final value = metric.of(m);
    final isCurrent = picked == months.length - 1;
    final neutral = metric == TrendMetric.purchases;
    // The current month is only partly over: compare it with the same days of
    // last month and of a year ago. Earlier months compare whole months.
    final day = DateFormat('d');
    final changes = <Widget>[
      if (isCurrent) ...[
        if (trend.lastMonthSoFar case final d?)
          if (percentChange(value, metric.ofDays(d)) case final c?)
            _Change(change: c, against: '${day.format(d.from)}–${DateFormat('d MMM').format(d.to)}', neutral: neutral),
        if (trend.lastYearSoFar case final d?)
          if (percentChange(value, metric.ofDays(d)) case final c?)
            _Change(change: c, against: '${day.format(d.from)}–${DateFormat('d MMM y').format(d.to)}', neutral: neutral),
      ] else if (picked > 0)
        if (percentChange(value, metric.of(months[picked - 1])) case final c?)
          _Change(change: c, against: DateFormat('MMM').format(months[picked - 1].month), neutral: neutral),
    ];
    final total = months.fold(Money.zero, (sum, x) => sum + metric.of(x));
    final best = months.reduce((a, b) => metric.of(b).compareTo(metric.of(a)) > 0 ? b : a);
    final totalSales = months.fold(Money.zero, (sum, x) => sum + x.sales);
    final totalCollected = months.fold(Money.zero, (sum, x) => sum + x.collections);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${metric.label} · ${DateFormat('MMMM y').format(m.month)}${isCurrent ? ' (so far)' : ''}',
          style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        Text(
          formatInr(value),
          key: const Key('trend-value'),
          style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (changes.isNotEmpty) Wrap(spacing: Insets.m, runSpacing: Insets.xs, children: changes),
        Text(_detail(m), style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
        const SizedBox(height: Insets.l),
        _Bars(months: months, metric: metric, picked: picked, onPick: onPick),
        const Divider(height: Insets.xl),
        Row(
          children: [
            Expanded(
              child: _Figure(label: 'Total, ${months.length} months', value: formatInrCompact(total)),
            ),
            Expanded(
              child: _Figure(label: 'Monthly average', value: formatInrCompact(Money((total.paise / months.length).round()))),
            ),
            Expanded(
              child: _Figure(
                label: 'Best month',
                value: metric.of(best).isPositive ? DateFormat('MMM y').format(best.month) : '—',
              ),
            ),
          ],
        ),
        if (metric != TrendMetric.purchases && totalSales.isPositive) ...[
          const SizedBox(height: Insets.m),
          Text(
            'Collected ${(totalCollected.paise * 100 / totalSales.paise).round()}% of sales in these months '
            '(${formatInrCompact(totalCollected)} of ${formatInrCompact(totalSales)})',
            key: const Key('trend-collected'),
            style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  String _detail(TrendMonth m) => switch (metric) {
    TrendMetric.sales => [
      plural(m.bills, 'bill'),
      '${plural(m.buyers, 'shop')} bought',
      if (m.returns.isPositive) '${formatInr(m.returns)} returned',
    ].join(' · '),
    TrendMetric.collections => m.sales.isPositive ? 'Sales that month ${formatInr(m.sales)}' : 'No sales that month',
    TrendMetric.purchases => plural(m.purchaseBills, 'purchase bill'),
  };
}

/// "↑ 12% vs Oct": up is good for sales and collections (green), down is
/// red; purchases are [neutral] (more buying is neither good nor bad).
class _Change extends StatelessWidget {
  const _Change({required this.change, required this.against, this.neutral = false});

  final double change;
  final String against;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final up = change >= 0;
    final color = neutral || change.abs() < 0.5
        ? context.colors.onSurfaceVariant
        : (up ? context.semantic.credit : context.semantic.owed);
    final pct = change.abs() >= 10 ? change.abs().round().toString() : change.abs().toStringAsFixed(1);
    final style = context.text.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600);
    return Semantics(
      label: '${up ? 'Up' : 'Down'} $pct% versus $against',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 16, color: color),
          Text('$pct% vs $against', style: style),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
      Text(value, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
    ],
  );
}

/// One bar per month, height ∝ amount; tap a bar to read that month.
class _Bars extends StatelessWidget {
  const _Bars({required this.months, required this.metric, required this.picked, required this.onPick});

  final List<TrendMonth> months;
  final TrendMetric metric;
  final int picked;
  final ValueChanged<int> onPick;

  static const _height = 120.0;

  @override
  Widget build(BuildContext context) {
    final maxPaise = months.fold(0, (mx, m) => metric.of(m).paise > mx ? metric.of(m).paise : mx);
    final many = months.length > 6;
    return SizedBox(
      height: _height + 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, m) in months.indexed)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == picked,
                label: '${DateFormat('MMMM y').format(m.month)}: ${formatInr(metric.of(m))}',
                excludeSemantics: true,
                child: InkWell(
                  key: Key('trend-bar-$i'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => onPick(i),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: many ? 2 : 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: maxPaise == 0
                              ? 2
                              : (_height * metric.of(m).paise / maxPaise).clamp(metric.of(m).isPositive ? 3.0 : 2.0, _height),
                          decoration: BoxDecoration(
                            color: i == picked ? context.colors.primary : context.colors.primary.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: Insets.xs),
                        SizedBox(
                          height: 20,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              many ? DateFormat('MMMMM').format(m.month) : DateFormat('MMM').format(m.month),
                              style: context.text.labelSmall?.copyWith(
                                color: i == picked ? context.colors.primary : context.colors.onSurfaceVariant,
                                fontWeight: i == picked ? FontWeight.w700 : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Owner: the shops that bought most over the trend's months.
class TopBuyersCard extends ConsumerWidget {
  const TopBuyersCard({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final months = ref.watch(trendMonthsProvider);
    final trend = ref.watch(businessTrendProvider(companyId)).value;
    if (trend == null || trend.topBuyers.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Insets.xl),
        Text('Top customers · last $months months', style: context.text.titleMedium),
        const SizedBox(height: Insets.s),
        Card.outlined(
          key: const Key('top-buyers'),
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, b) in trend.topBuyers.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  onTap: () => context.push('/shop/${b.shopId}'),
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: context.colors.secondaryContainer,
                    child: Text('${i + 1}', style: context.text.labelMedium),
                  ),
                  title: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      plural(b.bills, 'bill'),
                      if (b.receivable.isPositive) 'owes ${formatInrCompact(b.receivable)}',
                      ?b.siteName,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(formatInrCompact(b.sales), style: context.text.titleSmall),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
