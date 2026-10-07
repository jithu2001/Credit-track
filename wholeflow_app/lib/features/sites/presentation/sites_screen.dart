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
import '../../home/refresh.dart';
import '../../shops/domain/shop.dart';
import '../../shops/presentation/shop_list_controller.dart';
import '../../visits/presentation/location_providers.dart';
import '../../visits/presentation/visits_view.dart';
import '../domain/site.dart';
import 'site_providers.dart';

/// Owner tab: each site with its shops, dues, sales and collections for a period.
class SitesScreen extends ConsumerWidget {
  const SitesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(activeCompanyProvider).value;
    final period = ref.watch(reportPeriodControllerProvider);
    final report = company == null ? null : ref.watch(siteReportProvider(company.id));
    final tab = ref.watch(sitesTabControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const CompanyTitle(screen: 'Sites'),
        actions: [
          Builder(
            builder: (context) {
              final n = ref.watch(pendingSuggestionsProvider).value?.length ?? 0;
              return IconButton(
                tooltip: n == 0 ? 'Shop locations to review' : '$n shop locations to review',
                onPressed: () {
                  ref.invalidate(pendingSuggestionsProvider);
                  context.push('/locations/review');
                },
                icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.where_to_vote_outlined)),
              );
            },
          ),
          const AccountButton(),
        ],
      ),
      floatingActionButton: company == null || tab != SitesTab.sites
          ? null
          : FloatingActionButton.extended(
              key: const Key('new-site'),
              onPressed: () => context.push('/sites/new'),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('New site'),
            ),
      body: company == null
          ? const SizedBox.shrink()
          : Column(
              children: [
                ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, 0),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<SitesTab>(
                        key: const Key('sites-tab'),
                        segments: const [
                          ButtonSegment(value: SitesTab.sites, label: Text('Sites'), icon: Icon(Icons.location_city_outlined)),
                          ButtonSegment(value: SitesTab.visits, label: Text('Visits'), icon: Icon(Icons.where_to_vote_outlined)),
                        ],
                        selected: {tab},
                        onSelectionChanged: (s) => ref.read(sitesTabControllerProvider.notifier).set(s.first),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: tab == SitesTab.visits
                      ? VisitsView(company: company)
                      : RefreshIndicator(
                          onRefresh: () => refreshCompanyData(ref),
                          child: ContentWidth(
                            child: CustomScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                SliverToBoxAdapter(
                                  child: SizedBox(
                                    height: 56,
                                    child: ListView(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.s),
                                      children: [
                                        for (final p in ReportPeriod.values) ...[
                                          ChoiceChip(
                                            label: Text(p.label),
                                            selected: p == period,
                                            onSelected: (_) => ref.read(reportPeriodControllerProvider.notifier).set(p),
                                          ),
                                          const SizedBox(width: Insets.s),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                ...switch (report!) {
                                  AsyncValue(:final value?) => [
                                    if (!value.any((r) => !r.isNoSite))
                                      const SliverToBoxAdapter(
                                        child: Padding(
                                          padding: EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, Insets.s),
                                          child: _NoSitesYet(),
                                        ),
                                      ),
                                    SliverPadding(
                                      padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, 96),
                                      sliver: SliverList.separated(
                                        itemCount: value.length,
                                        separatorBuilder: (_, _) => const SizedBox(height: Insets.m),
                                        itemBuilder: (context, i) => _SiteCard(row: value[i]),
                                      ),
                                    ),
                                  ],
                                  AsyncValue(:final error?) => [
                                    SliverToBoxAdapter(
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: Insets.xxl),
                                        child: ErrorState(
                                          error: error,
                                          onRetry: () => ref.invalidate(siteReportProvider(company.id)),
                                        ),
                                      ),
                                    ),
                                  ],
                                  _ => [SliverList.list(children: List.filled(4, const SkeletonTile()))],
                                },
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _NoSitesYet extends StatelessWidget {
  const _NoSitesYet();

  @override
  Widget build(BuildContext context) {
    return Card.filled(
      color: context.colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(Insets.l),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline_rounded, color: context.colors.onSecondaryContainer),
            const SizedBox(width: Insets.m),
            Expanded(
              child: Text(
                'Group your shops into sites, like a town or a route. Then give staff only the sites they handle, '
                'and see dues and sales for each site here.',
                style: context.text.bodyMedium?.copyWith(color: context.colors.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SiteCard extends ConsumerWidget {
  const _SiteCard({required this.row});

  final SiteReportRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (row.isNoSite) {
            // Shops in no site: the shop list, filtered to them.
            ref.read(shopFilterControllerProvider.notifier).setSites(const {ShopFilter.noSite});
            ref.read(shopsViewControllerProvider.notifier).set(ShopsView.all);
            context.go('/shops');
          } else {
            context.push('/sites/${row.siteId}');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(Insets.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(row.isNoSite ? Icons.help_outline_rounded : Icons.location_city_outlined, size: 20),
                  const SizedBox(width: Insets.s),
                  Expanded(
                    child: Text(
                      row.isNoSite ? 'Shops in no site' : row.label,
                      style: context.text.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(plural(row.shops, 'shop'), style: muted),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: Insets.m),
              SiteFigures(row: row),
            ],
          ),
        ),
      ),
    );
  }
}

/// Outstanding, sales and collections of one report row, in a wrapping row.
class SiteFigures extends StatelessWidget {
  const SiteFigures({super.key, required this.row});

  final SiteReportRow row;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Insets.xl,
      runSpacing: Insets.m,
      children: [
        _Figure(
          label: 'Outstanding',
          value: row.outstanding,
          detail: '${plural(row.shopsWithDues, 'shop')} owe',
          color: row.outstanding.isPositive ? context.semantic.owed : null,
        ),
        if (row.sales != null)
          _Figure(
            label: 'Sales',
            value: row.sales!,
            detail: row.returns != null && row.returns!.isPositive ? 'returns ${formatInrCompact(row.returns!)}' : null,
          ),
        if (row.collections != null) _Figure(label: 'Collected', value: row.collections!, color: context.semantic.credit),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.detail, this.color});

  final String label;
  final Money value;
  final String? detail;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final muted = context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant);
    return Semantics(
      container: true,
      label: '$label ${formatInr(value)}${detail == null ? '' : ', $detail'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: muted),
          Text(
            formatInrCompact(value),
            style: context.text.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
          if (detail != null) Text(detail!, style: muted),
        ],
      ),
    );
  }
}
