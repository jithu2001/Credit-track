import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/share.dart';
import '../../../core/widgets/states.dart';
import '../../analytics/presentation/analytics_providers.dart';
import '../../analytics/presentation/analytics_widgets.dart';
import '../../company/domain/company.dart';
import '../../shops/data/shop_repository.dart';
import '../../shops/presentation/shop_tile.dart';
import '../../sites/domain/site.dart';
import '../data/overdue_repository.dart';
import '../data/report_pdf.dart';
import '../domain/outstanding_report.dart';
import '../domain/overdue_report.dart';

part 'outstanding_views.g.dart';

@riverpod
Future<OutstandingReport> outstandingReport(Ref ref, Company company) async {
  final shops = await ref.watch(shopRepositoryProvider).outstanding(company.id);
  return buildOutstandingReport(companyName: company.companyName, shops: shops, generatedAt: DateTime.now());
}

/// Shops past the credit period; the period is shared with Analytics.
@riverpod
Future<OverdueReport> overdueReport(Ref ref, Company company) async {
  final days = ref.watch(creditDaysProvider);
  final now = DateTime.now();
  final shops = await ref.watch(overdueRepositoryProvider).overdue(company.id, creditDays: days, today: now);
  return buildOverdueReport(companyName: company.companyName, creditDays: days, shops: shops, generatedAt: now);
}

enum OverdueSort {
  site('By site'),
  amount('Most overdue first'),
  days('Most days late first'),
  name('Name A–Z');

  const OverdueSort(this.label);
  final String label;
}

/// How Shops → Overdue orders its shops. A view setting only: kept in memory.
@Riverpod(keepAlive: true)
class OverdueSortController extends _$OverdueSortController {
  @override
  OverdueSort build() => OverdueSort.site;

  void set(OverdueSort s) => state = s;
}

/// Every shop in [report] as one list, for the sorts other than by site.
List<OverdueShop> sortedOverdueShops(OverdueReport report, OverdueSort sort) {
  int byName(OverdueShop a, OverdueShop b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
  final list = [for (final g in report.groups) ...g.shops];
  switch (sort) {
    case OverdueSort.site:
      break;
    case OverdueSort.amount:
      list.sort((a, b) {
        final c = b.overdue.compareTo(a.overdue);
        return c != 0 ? c : byName(a, b);
      });
    case OverdueSort.days:
      list.sort((a, b) {
        final c = b.maxDaysOverdue.compareTo(a.maxDaysOverdue);
        return c != 0 ? c : b.overdue.compareTo(a.overdue);
      });
    case OverdueSort.name:
      list.sort(byName);
  }
  return list;
}

/// Shops whose name, phone, site or Tally area contains [query].
bool _matches(String query, String name, String? phone, String? area, String? site) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return name.toLowerCase().contains(q) ||
      (phone ?? '').toLowerCase().contains(q) ||
      (area ?? '').toLowerCase().contains(q) ||
      siteLabel(site).toLowerCase().contains(q);
}

/// [report] narrowed to the shops matching the search, with totals recomputed.
OutstandingReport filterDuesReport(OutstandingReport report, String query) => query.trim().isEmpty
    ? report
    : buildOutstandingReport(
        companyName: report.companyName,
        generatedAt: report.generatedAt,
        shops: [
          for (final g in report.groups)
            for (final s in g.shops)
              if (_matches(query, s.name, s.phone, s.area, s.siteName)) s,
        ],
      );

/// [report] narrowed to the shops matching the search, with totals recomputed.
OverdueReport filterOverdueReport(OverdueReport report, String query) => query.trim().isEmpty
    ? report
    : buildOverdueReport(
        companyName: report.companyName,
        creditDays: report.creditDays,
        generatedAt: report.generatedAt,
        shops: [
          for (final g in report.groups)
            for (final s in g.shops)
              if (_matches(query, s.name, s.phone, s.area, s.siteName)) s,
        ],
      );

Future<void> shareDuesReport(BuildContext context, OutstandingReport report) => _share(
  context,
  subject: 'Outstanding — ${report.companyName}',
  fileStem: 'outstanding-${fileSlug(report.companyName)}',
  text: () => outstandingReportText(report),
  pdf: () => outstandingReportPdf(report),
);

Future<void> shareOverdueReport(BuildContext context, OverdueReport report) => _share(
  context,
  subject: 'Past ${plural(report.creditDays, 'day')} credit — ${report.companyName}',
  fileStem: 'overdue-${report.creditDays}d-${fileSlug(report.companyName)}',
  text: () => overdueReportText(report),
  pdf: () => overdueReportPdf(report),
);

Future<void> _share(
  BuildContext context, {
  required String subject,
  required String fileStem,
  required String Function() text,
  required Future<Uint8List> Function() pdf,
}) async {
  final format = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.notes_rounded),
            title: const Text('Share as text'),
            subtitle: const Text('Good for WhatsApp'),
            onTap: () => Navigator.pop(context, 'text'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Share as PDF'),
            onTap: () => Navigator.pop(context, 'pdf'),
          ),
          const SizedBox(height: Insets.s),
        ],
      ),
    ),
  );
  if (format == null) return;
  try {
    if (format == 'text') {
      await shareText(text(), subject: subject);
    } else {
      await sharePdf(await pdf(), fileStem: fileStem, subject: subject);
    }
  } catch (e) {
    if (context.mounted) showMessage(context, AppFailure.from(e).message);
  }
}

/// Shops that owe money, grouped by area with a grand total (Shops → Dues).
class DuesView extends ConsumerWidget {
  const DuesView({super.key, required this.company, required this.report, this.searching = false});

  final Company company;
  final AsyncValue<OutstandingReport> report;
  final bool searching;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (report) {
      AsyncValue(:final value?) when value.groups.isEmpty => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: Insets.xxl),
          searching
              ? const _NoMatch()
              : const EmptyState(
                  icon: Icons.celebration_outlined,
                  title: 'Nothing outstanding',
                  message: 'No shop owes anything right now.',
                ),
        ],
      ),
      AsyncValue(:final value?) => ContentWidth(child: _ReportList(report: value)),
      AsyncValue(:final error?) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: Insets.xxl),
          ErrorState(error: error, onRetry: () => ref.invalidate(outstandingReportProvider(company))),
        ],
      ),
      _ => const SkeletonList(),
    };
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.label, required this.amount, required this.detail});

  final String label;
  final Money amount;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Card.filled(
      color: semantic.owedContainer,
      child: Padding(
        padding: const EdgeInsets.all(Insets.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: context.text.labelLarge?.copyWith(color: semantic.onOwedContainer)),
            Text(
              formatInr(amount),
              style: context.text.headlineSmall?.copyWith(color: semantic.onOwedContainer, fontWeight: FontWeight.w600),
            ),
            Text(detail, style: context.text.bodySmall?.copyWith(color: semantic.onOwedContainer)),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.amount});

  final String title;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.colors.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.m),
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.text.titleSmall)),
          Text(formatInr(amount), style: context.text.titleSmall),
        ],
      ),
    );
  }
}

class _ReportList extends StatelessWidget {
  const _ReportList({required this.report});

  final OutstandingReport report;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(Insets.l),
          sliver: SliverToBoxAdapter(
            child: _TotalCard(
              label: 'Grand total',
              amount: report.total,
              detail: '${plural(report.shopCount, 'shop')} in ${plural(report.groups.length, 'site')}',
            ),
          ),
        ),
        for (final g in report.groups) ...[
          SliverToBoxAdapter(
            child: _GroupHeader(title: '${g.site} (${g.shops.length})', amount: g.subtotal),
          ),
          SliverList.separated(
            itemCount: g.shops.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: Insets.l),
            itemBuilder: (context, i) => ShopTile(shop: g.shops[i], showSite: false),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: Insets.xxl)),
      ],
    );
  }
}

class _NoMatch extends StatelessWidget {
  const _NoMatch();

  @override
  Widget build(BuildContext context) =>
      const EmptyState(icon: Icons.search_off_rounded, title: 'No shops match', message: 'Try a different search.');
}

/// Shops past the credit period (Shops → Overdue). The credit-period chips
/// stay on top while the list loads, fails or is empty.
class OverdueView extends StatelessWidget {
  const OverdueView({
    super.key,
    required this.report,
    required this.onRetry,
    this.searching = false,
    this.sort = OverdueSort.site,
  });

  final AsyncValue<OverdueReport> report;
  final VoidCallback onRetry;
  final bool searching;
  final OverdueSort sort;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: CreditDaysFilter()),
        ...switch (report) {
          AsyncValue(:final value?) when value.groups.isEmpty => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: Insets.xl),
                child: searching
                    ? const _NoMatch()
                    : EmptyState(
                        icon: Icons.verified_outlined,
                        title: 'No shop is past the limit',
                        message: 'Every unpaid bill is within ${plural(value.creditDays, 'day')}.',
                      ),
              ),
            ),
          ],
          AsyncValue(:final value?) => _reportSlivers(context, value),
          AsyncValue(:final error?) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: Insets.xl),
                child: ErrorState(error: error, onRetry: onRetry),
              ),
            ),
          ],
          _ => [SliverList.list(children: List.filled(6, const SkeletonTile()))],
        },
        const SliverToBoxAdapter(child: SizedBox(height: Insets.xxl)),
      ],
    );
  }

  Widget _flatList(List<OverdueShop> shops) => SliverList.separated(
    itemCount: shops.length,
    separatorBuilder: (_, _) => const Divider(height: 1, indent: Insets.l),
    itemBuilder: (context, i) => OverdueShopTile(key: ValueKey(shops[i].id), shop: shops[i], showSite: true),
  );

  List<Widget> _reportSlivers(BuildContext context, OverdueReport r) => [
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, 0),
      sliver: SliverToBoxAdapter(
        child: Text(
          'Each payment clears the oldest unpaid bill first. A bill is past the limit '
          '${plural(r.creditDays, 'day')} after its date.',
          style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
        ),
      ),
    ),
    SliverPadding(
      padding: const EdgeInsets.all(Insets.l),
      sliver: SliverToBoxAdapter(
        child: _TotalCard(
          label: 'Past ${plural(r.creditDays, 'day')}',
          amount: r.total,
          detail: '${plural(r.shopCount, 'shop')} in ${plural(r.groups.length, 'site')}',
        ),
      ),
    ),
    if (sort == OverdueSort.site)
      for (final g in r.groups) ...[
        SliverToBoxAdapter(
          child: _GroupHeader(title: '${g.site} (${g.shops.length})', amount: g.subtotal),
        ),
        SliverList.separated(
          itemCount: g.shops.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: Insets.l),
          itemBuilder: (context, i) => OverdueShopTile(key: ValueKey(g.shops[i].id), shop: g.shops[i]),
        ),
      ]
    else
      _flatList(sortedOverdueShops(r, sort)),
  ];
}

/// A shop past the limit. With bills it expands to list them; without (staff
/// who may not see transactions) it opens the shop like any other tile.
class OverdueShopTile extends StatefulWidget {
  const OverdueShopTile({super.key, required this.shop, this.showSite = false});

  final OverdueShop shop;

  /// In the flat sorts there are no site headers, so the row names its site.
  final bool showSite;

  @override
  State<OverdueShopTile> createState() => _OverdueShopTileState();
}

class _OverdueShopTileState extends State<OverdueShopTile> {
  bool _expanded = false;

  void _openShop() {
    dismissKeyboard();
    context.push('/shop/${widget.shop.id}');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.shop;
    final bills = s.bills;
    final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    final owed = context.text.titleSmall?.copyWith(
      color: context.semantic.owed,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final details = [
      if (widget.showSite) siteLabel(s.siteName),
      daysPastLimit(s.maxDaysOverdue),
      plural(s.billCount, 'bill'),
      if (s.phone != null && s.phone!.trim().isNotEmpty) s.phone!.trim(),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: bills == null ? _openShop : () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Insets.l, Insets.m, Insets.m, Insets.m),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: context.text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: Insets.xs),
                      Text(details, style: muted),
                    ],
                  ),
                ),
                const SizedBox(width: Insets.m),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatInr(s.overdue), style: owed),
                    Text('of ${formatInr(s.receivable)}', style: muted),
                  ],
                ),
                if (bills != null)
                  Padding(
                    padding: const EdgeInsets.only(left: Insets.xs),
                    child: Icon(
                      _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      semanticLabel: _expanded ? 'Hide bills' : 'Show bills',
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (bills != null && _expanded) ...[
          for (final b in bills) _BillRow(bill: b),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: Insets.s, bottom: Insets.s),
              child: TextButton.icon(
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Open shop'),
                onPressed: _openShop,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.bill});

  final OverdueBill bill;

  @override
  Widget build(BuildContext context) {
    final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    final partlyPaid = bill.remaining != bill.amount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.xl, Insets.xs, Insets.xl + Insets.m, Insets.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bill.voucher ?? 'Bill', style: context.text.bodyMedium),
                Text(
                  partlyPaid ? '${formatDate(bill.date)} · bill ${formatInr(bill.amount)}, part paid' : formatDate(bill.date),
                  style: muted,
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.m),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatInr(bill.remaining), style: context.text.bodyMedium),
              Text(daysPastLimit(bill.daysOverdue), style: muted),
            ],
          ),
        ],
      ),
    );
  }
}
