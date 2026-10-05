import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../company/presentation/company_providers.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../../outstanding/presentation/outstanding_views.dart';
import '../../shops/presentation/shop_list_controller.dart';
import '../../shops/presentation/shop_tile.dart';
import '../../staff/presentation/staff_providers.dart';
import '../data/site_repository.dart';
import '../domain/site.dart';
import 'site_providers.dart';
import 'sites_screen.dart';

/// One site: its figures for the chosen period, its shops and who has it.
class SiteDetailScreen extends ConsumerWidget {
  const SiteDetailScreen({super.key, required this.siteId});

  final String siteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(activeCompanyProvider).value;
    final report = company == null ? null : ref.watch(siteReportProvider(company.id));
    final row = report?.value?.where((r) => r.siteId == siteId).firstOrNull;
    final shops = ref.watch(siteShopsProvider(siteId));
    final period = ref.watch(reportPeriodControllerProvider);
    final name = row?.label ?? 'Site';
    return Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (row != null)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) => switch (v) {
                'rename' => _rename(context, ref, row),
                'delete' => _delete(context, ref, row),
                _ => null,
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete site')),
              ],
            ),
        ],
      ),
      floatingActionButton: row == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('edit-site-shops'),
              onPressed: () => context.push('/sites/$siteId/edit'),
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: const Text('Choose shops'),
            ),
      body: switch (report) {
        null => const SizedBox.shrink(),
        AsyncValue(hasValue: true) when row == null => const EmptyState(
          icon: Icons.location_off_outlined,
          title: 'This site no longer exists',
        ),
        AsyncValue(hasValue: true) => RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(siteReportProvider(company!.id))
              ..invalidate(siteShopsProvider(siteId));
            await ref.read(siteShopsProvider(siteId).future);
          },
          child: ContentWidth(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                Padding(
                  padding: const EdgeInsets.all(Insets.l),
                  child: Card.filled(
                    child: Padding(
                      padding: const EdgeInsets.all(Insets.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${plural(row!.shops, 'shop')} · ${period.label}',
                            style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: Insets.m),
                          SiteFigures(row: row),
                        ],
                      ),
                    ),
                  ),
                ),
                _StaffWithSite(siteId: siteId),
                const _Header('Shops'),
                ...switch (shops) {
                  AsyncValue(:final value?) when value.isEmpty => [
                    const Padding(
                      padding: EdgeInsets.only(top: Insets.xl),
                      child: EmptyState(
                        icon: Icons.storefront_outlined,
                        title: 'No shops in this site yet',
                        message: 'Tap Choose shops to add some.',
                      ),
                    ),
                  ],
                  AsyncValue(:final value?) => [for (final s in value) ShopTile(shop: s, showSite: false)],
                  AsyncValue(:final error?) => [
                    ErrorTile(error: error, onRetry: () => ref.invalidate(siteShopsProvider(siteId))),
                  ],
                  _ => [const SkeletonTile(), const SkeletonTile(), const SkeletonTile()],
                },
              ],
            ),
          ),
        ),
        AsyncValue(:final error?) => ErrorState(error: error, onRetry: () => ref.invalidate(siteReportProvider(company!.id))),
        _ => const SkeletonList(),
      },
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, SiteReportRow row) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => SiteNameDialog(title: 'Rename site', initial: row.label),
    );
    if (name == null || name == row.label || !context.mounted) return;
    try {
      await ref.read(siteRepositoryProvider).rename(siteId, name);
      invalidateSiteData(ref);
    } on AppFailure catch (f) {
      if (context.mounted) showMessage(context, f.message);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, SiteReportRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${row.label}?'),
        content: Text(
          'Its ${plural(row.shops, 'shop')} will be in no site. Staff who had only this site lose these shops, '
          'and planned visits for it stop.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.colors.error, foregroundColor: context.colors.onError),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(siteRepositoryProvider).delete(siteId);
      invalidateSiteData(ref);
      if (context.mounted) {
        showMessage(context, '${row.label} deleted');
        context.pop();
      }
    } on AppFailure catch (f) {
      if (context.mounted) showMessage(context, f.message);
    }
  }
}

/// Staff given this site specifically; full-company staff see it too.
class _StaffWithSite extends ConsumerWidget {
  const _StaffWithSite({required this.siteId});

  final String siteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(staffMembersProvider).value;
    if (staff == null) return const SizedBox.shrink();
    final withSite = [
      for (final m in staff)
        if (!m.isOwner && m.isActive && m.companies.any((a) => !a.fullCompany && a.siteIds.contains(siteId))) m,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.badge_outlined, size: 20, color: context.colors.onSurfaceVariant),
          const SizedBox(width: Insets.m),
          Expanded(
            child: Text(
              withSite.isEmpty
                  ? 'No staff have this site on its own. Staff with the full company see these shops.'
                  : '${withSite.map((m) => m.displayName).join(', ')}, and staff with the full company.',
              style: context.text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    color: context.colors.surfaceContainer,
    padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.m),
    child: Text(text, style: context.text.titleSmall),
  );
}

/// Asks for a site name; pops the trimmed name.
class SiteNameDialog extends StatefulWidget {
  const SiteNameDialog({super.key, required this.title, this.initial = ''});

  final String title;
  final String initial;

  @override
  State<SiteNameDialog> createState() => _SiteNameDialogState();
}

class _SiteNameDialogState extends State<SiteNameDialog> {
  late final _name = TextEditingController(text: widget.initial);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('site-name'),
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Site name', hintText: 'e.g. Thodupuzha town'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
          onFieldSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// After sites or their shops change: every list that shows sites or groups by them.
void invalidateSiteData(WidgetRef ref) {
  ref
    ..invalidate(companySitesProvider)
    ..invalidate(allSitesProvider)
    ..invalidate(siteReportProvider)
    ..invalidate(siteShopsProvider)
    ..invalidate(companySiteShopsProvider)
    ..invalidate(shopListProvider)
    ..invalidate(outstandingReportProvider)
    ..invalidate(overdueReportProvider)
    ..invalidate(topDuesProvider);
}
