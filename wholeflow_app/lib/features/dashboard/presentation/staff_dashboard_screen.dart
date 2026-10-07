import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../company/domain/company.dart';
import '../../company/presentation/company_providers.dart';
import '../../company/presentation/company_switcher.dart';
import '../../home/account_button.dart';
import '../../home/refresh.dart';
import '../../shops/presentation/shop_list_controller.dart';
import '../../shops/presentation/shop_tile.dart';
import 'dashboard_providers.dart';
import 'dashboard_widgets.dart';
import 'freshness_banner.dart';

const _autoRefresh = Duration(minutes: 5);

/// Lightweight dashboard for staff.
/// Omits heavy business-wide analytics and overdue FIFO calculations to keep
/// memory and CPU overhead low on budget 1–2 GB phones.
class StaffDashboardScreen extends ConsumerStatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  ConsumerState<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends ConsumerState<StaffDashboardScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
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
              child: ContentWidth(child: _StaffDashboardBody(company: company)),
            ),
    );
  }
}

class _StaffDashboardBody extends ConsumerWidget {
  const _StaffDashboardBody({required this.company});

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
          AsyncValue(:final value?) => StatGrid(
              tiles: [
                StatData(
                  'Total outstanding',
                  formatInrCompact(value.totalOutstanding),
                  formatInr(value.totalOutstanding),
                  tone: StatTone.owed,
                ),
                if (showSales)
                  StatData(
                    'Sales this month',
                    sales == null ? '—' : formatInrCompact(sales.amount),
                    sales == null
                        ? 'Loading…'
                        : '${formatInr(sales.amount)} · ${plural(sales.bills, 'bill')} in ${DateFormat('MMMM').format(sales.month)}',
                  ),
                StatData('Shops with dues', '${value.shopsWithDues}', 'of ${value.shops} shops'),
                StatData('Shops', '${value.shops}', 'active in Tally'),
              ],
            ),
          AsyncValue(:final error?) => ErrorState(error: error, onRetry: () => refreshCompanyData(ref)),
          AsyncValue(hasValue: true) => const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'No figures yet',
              message: 'Figures appear after the first sync from Tally.',
            ),
          _ => const StatGrid(tiles: null),
        },
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
                  for (final (i, shop) in value.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ShopTile(shop: shop),
                  ],
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
