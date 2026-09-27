import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../company/domain/company.dart';
import '../../company/presentation/company_providers.dart';
import '../../company/presentation/company_switcher.dart';
import '../../home/refresh.dart';
import '../../shops/data/shop_repository.dart';
import '../../shops/presentation/shop_tile.dart';
import '../data/report_pdf.dart';
import '../domain/outstanding_report.dart';

part 'outstanding_screen.g.dart';

@riverpod
Future<OutstandingReport> outstandingReport(Ref ref, Company company) async {
  final shops = await ref.watch(shopRepositoryProvider).outstanding(company.id);
  return buildOutstandingReport(companyName: company.companyName, shops: shops, generatedAt: DateTime.now());
}

class OutstandingScreen extends ConsumerWidget {
  const OutstandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(activeCompanyProvider).value;
    final report = company == null ? null : ref.watch(outstandingReportProvider(company));
    final loaded = report?.value;
    return Scaffold(
      appBar: AppBar(
        title: const CompanyTitle(screen: 'Outstanding'),
        actions: [
          IconButton(
            tooltip: 'Share report',
            icon: const Icon(Icons.share_rounded),
            onPressed: loaded == null || loaded.groups.isEmpty ? null : () => _share(context, loaded),
          ),
        ],
      ),
      body: report == null
          ? const SizedBox.shrink()
          : RefreshIndicator(
              onRefresh: () => refreshCompanyData(ref),
              child: switch (report) {
                AsyncValue(:final value?) when value.groups.isEmpty => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: Insets.xxl),
                    EmptyState(
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
                    ErrorState(error: error, onRetry: () => ref.invalidate(outstandingReportProvider(company!))),
                  ],
                ),
                _ => const SkeletonList(),
              },
            ),
    );
  }

  Future<void> _share(BuildContext context, OutstandingReport report) async {
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
      final subject = 'Outstanding — ${report.companyName}';
      if (format == 'text') {
        await SharePlus.instance.share(ShareParams(text: outstandingReportText(report), subject: subject));
      } else {
        final bytes = await outstandingReportPdf(report);
        final slug = report.companyName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
        final name = 'outstanding-${slug.toLowerCase()}.pdf';
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

class _ReportList extends StatelessWidget {
  const _ReportList({required this.report});

  final OutstandingReport report;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(Insets.l),
          sliver: SliverToBoxAdapter(
            child: Card.filled(
              color: semantic.owedContainer,
              child: Padding(
                padding: const EdgeInsets.all(Insets.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Grand total', style: context.text.labelLarge?.copyWith(color: semantic.onOwedContainer)),
                    Text(
                      formatInr(report.total),
                      style: context.text.headlineSmall?.copyWith(color: semantic.onOwedContainer, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${report.shopCount} shops in ${report.groups.length} areas',
                      style: context.text.bodySmall?.copyWith(color: semantic.onOwedContainer),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        for (final g in report.groups) ...[
          SliverToBoxAdapter(
            child: Container(
              color: context.colors.surfaceContainer,
              padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.m),
              child: Row(
                children: [
                  Expanded(child: Text('${g.area} (${g.shops.length})', style: context.text.titleSmall)),
                  Text(formatInr(g.subtotal), style: context.text.titleSmall),
                ],
              ),
            ),
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
