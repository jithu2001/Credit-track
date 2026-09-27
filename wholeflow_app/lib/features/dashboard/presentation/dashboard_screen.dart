import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../company/domain/company.dart';
import '../../company/presentation/company_providers.dart';
import '../../company/presentation/company_switcher.dart';
import '../../home/refresh.dart';
import '../../shops/presentation/shop_tile.dart';
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
      appBar: AppBar(title: const CompanyTitle(screen: 'Dashboard')),
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
              _Stat('Shops with dues', '${value.shopsWithDues}', 'of ${value.shops} shops'),
              _Stat('In credit', formatInrCompact(value.totalCredit), formatInr(value.totalCredit), tone: _Tone.credit),
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
        const SizedBox(height: Insets.xl),
        Row(
          children: [
            Expanded(child: Text('Top dues', style: context.text.titleMedium)),
            TextButton(onPressed: () => context.go('/outstanding'), child: const Text('View all')),
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

enum _Tone { neutral, owed, credit }

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
        final columns = constraints.maxWidth >= 720 ? 4 : 2;
        final width = (constraints.maxWidth - Insets.m * (columns - 1)) / columns;
        return Wrap(
          spacing: Insets.m,
          runSpacing: Insets.m,
          children: [
            for (var i = 0; i < 4; i++)
              SizedBox(width: width, child: tiles == null ? const _StatCardSkeleton() : _StatCard(tiles![i])),
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
      _Tone.credit => (semantic.creditContainer, semantic.onCreditContainer),
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
