import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../analytics/presentation/analytics_providers.dart';
import '../../analytics/presentation/analytics_widgets.dart';
import '../../company/domain/company.dart';
import '../../company/presentation/company_providers.dart';
import '../../company/presentation/company_switcher.dart';
import '../../home/account_button.dart';
import '../../home/refresh.dart';
import '../../shops/data/shop_repository.dart';
import '../../shops/presentation/shop_tile.dart';
import '../data/overdue_repository.dart';
import '../data/report_pdf.dart';
import '../domain/outstanding_report.dart';
import '../domain/overdue_report.dart';

part 'outstanding_screen.g.dart';

@riverpod
Future<OutstandingReport> outstandingReport(Ref ref, Company company) async {
  final shops = await ref.watch(shopRepositoryProvider).outstanding(company.id);
  return buildOutstandingReport(companyName: company.companyName, shops: shops, generatedAt: DateTime.now());
}

enum OutstandingView {
  all('All dues'),
  overdue('Past credit limit');

  const OutstandingView(this.label);
  final String label;
}

/// Which list the Outstanding screen shows. A view setting only: kept in memory.
@Riverpod(keepAlive: true)
class OutstandingViewController extends _$OutstandingViewController {
  @override
  OutstandingView build() => OutstandingView.all;

  void set(OutstandingView v) => state = v;
}

/// Shops past the credit period; the period is shared with Analytics.
@riverpod
Future<OverdueReport> overdueReport(Ref ref, Company company) async {
  final days = ref.watch(creditDaysProvider);
  final now = DateTime.now();
  final shops = await ref.watch(overdueRepositoryProvider).overdue(company.id, creditDays: days, today: now);
  return buildOverdueReport(companyName: company.companyName, creditDays: days, shops: shops, generatedAt: now);
}

class OutstandingScreen extends ConsumerWidget {
  const OutstandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(activeCompanyProvider).value;
    final view = ref.watch(outstandingViewControllerProvider);
    final report = company == null || view != OutstandingView.all ? null : ref.watch(outstandingReportProvider(company));
    final overdue = company == null || view != OutstandingView.overdue ? null : ref.watch(overdueReportProvider(company));
    final VoidCallback? onShare = switch (view) {
      OutstandingView.all => switch (report?.value) {
        final r? when r.groups.isNotEmpty => () => _shareAll(context, r),
        _ => null,
      },
      OutstandingView.overdue => switch (overdue?.value) {
        final r? when r.groups.isNotEmpty => () => _shareOverdue(context, r),
        _ => null,
      },
    };
    return Scaffold(
      appBar: AppBar(
        title: const CompanyTitle(screen: 'Outstanding'),
        actions: [
          IconButton(tooltip: 'Share report', icon: const Icon(Icons.share_rounded), onPressed: onShare),
          const AccountButton(),
        ],
      ),
      body: company == null
          ? const SizedBox.shrink()
          : Column(
              children: [
                ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, Insets.s),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<OutstandingView>(
                        key: const Key('outstanding-view'),
                        segments: [for (final v in OutstandingView.values) ButtonSegment(value: v, label: Text(v.label))],
                        selected: {view},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => ref.read(outstandingViewControllerProvider.notifier).set(s.first),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => refreshCompanyData(ref),
                    child: switch (view) {
                      OutstandingView.all => _AllDues(company: company, report: report!),
                      OutstandingView.overdue => ContentWidth(
                        child: _OverdueList(report: overdue!, onRetry: () => ref.invalidate(overdueReportProvider(company))),
                      ),
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _shareAll(BuildContext context, OutstandingReport report) => _share(
    context,
    subject: 'Outstanding — ${report.companyName}',
    fileStem: 'outstanding-${_slug(report.companyName)}',
    text: () => outstandingReportText(report),
    pdf: () => outstandingReportPdf(report),
  );

  Future<void> _shareOverdue(BuildContext context, OverdueReport report) => _share(
    context,
    subject: 'Past ${plural(report.creditDays, 'day')} credit — ${report.companyName}',
    fileStem: 'overdue-${report.creditDays}d-${_slug(report.companyName)}',
    text: () => overdueReportText(report),
    pdf: () => overdueReportPdf(report),
  );

  static String _slug(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '').toLowerCase();

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
        await SharePlus.instance.share(ShareParams(text: text(), subject: subject));
      } else {
        final bytes = await pdf();
        final name = '$fileStem.pdf';
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
            fileNameOverrides: [name],
            subject: subject,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) showMessage(context, AppFailure.from(e).message);
    }
  }
}

class _AllDues extends ConsumerWidget {
  const _AllDues({required this.company, required this.report});

  final Company company;
  final AsyncValue<OutstandingReport> report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (report) {
      AsyncValue(:final value?) when value.groups.isEmpty => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: Insets.xxl),
          EmptyState(icon: Icons.celebration_outlined, title: 'Nothing outstanding', message: 'No shop owes anything right now.'),
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

class _AreaHeader extends StatelessWidget {
  const _AreaHeader({required this.title, required this.amount});

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
              detail: '${report.shopCount} shops in ${report.groups.length} areas',
            ),
          ),
        ),
        for (final g in report.groups) ...[
          SliverToBoxAdapter(
            child: _AreaHeader(title: '${g.area} (${g.shops.length})', amount: g.subtotal),
          ),
          SliverList.separated(
            itemCount: g.shops.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: Insets.l),
            itemBuilder: (context, i) => ShopTile(shop: g.shops[i], showArea: false),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: Insets.xxl)),
      ],
    );
  }
}

/// Credit-period chips stay on top while the list loads, fails or is empty.
class _OverdueList extends StatelessWidget {
  const _OverdueList({required this.report, required this.onRetry});

  final AsyncValue<OverdueReport> report;
  final VoidCallback onRetry;

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
                child: EmptyState(
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
          detail: '${plural(r.shopCount, 'shop')} in ${plural(r.groups.length, 'area')}',
        ),
      ),
    ),
    for (final g in r.groups) ...[
      SliverToBoxAdapter(
        child: _AreaHeader(title: '${g.area} (${g.shops.length})', amount: g.subtotal),
      ),
      SliverList.separated(
        itemCount: g.shops.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: Insets.l),
        itemBuilder: (context, i) => OverdueShopTile(key: ValueKey(g.shops[i].id), shop: g.shops[i]),
      ),
    ],
  ];
}

/// A shop past the limit. With bills it expands to list them; without (staff
/// who may not see transactions) it opens the shop like any other tile.
class OverdueShopTile extends StatefulWidget {
  const OverdueShopTile({super.key, required this.shop});

  final OverdueShop shop;

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
