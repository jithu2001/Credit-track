import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../company/domain/company.dart';
import '../../company/presentation/company_providers.dart';
import '../../home/account_button.dart';
import '../domain/staff.dart';
import 'staff_providers.dart';

class StaffListScreen extends ConsumerStatefulWidget {
  const StaffListScreen({super.key});

  @override
  ConsumerState<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends ConsumerState<StaffListScreen> {
  /// "Who works for …?" filter; null = everyone.
  String? _companyFilter;

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(staffMembersProvider);
    final companies = ref.watch(companiesProvider).value ?? const <Company>[];
    final names = {for (final c in companies) c.id: c.companyName};
    return Scaffold(
      appBar: AppBar(title: const Text('Staff'), actions: const [AccountButton()]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/staff/new'),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add staff'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(staffMembersProvider.future),
        child: ContentWidth(
          child: switch (members) {
            AsyncValue(:final value?) => _buildList(context, value, companies, names),
            AsyncValue(:final error?) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: Insets.xxl),
                ErrorState(error: error, onRetry: () => ref.invalidate(staffMembersProvider)),
              ],
            ),
            _ => const SkeletonList(),
          },
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<StaffMember> all, List<Company> companies, Map<String, String> names) {
    final shown = _companyFilter == null
        ? all
        : all.where((m) => m.isOwner || m.companies.any((a) => a.companyId == _companyFilter)).toList();
    final staffCount = all.where((m) => !m.isOwner).length;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (companies.length > 1)
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.s),
              children: [
                ChoiceChip(
                  label: const Text('Everyone'),
                  selected: _companyFilter == null,
                  onSelected: (_) => setState(() => _companyFilter = null),
                ),
                for (final c in companies) ...[
                  const SizedBox(width: Insets.s),
                  ChoiceChip(
                    label: Text(c.companyName),
                    selected: _companyFilter == c.id,
                    onSelected: (_) => setState(() => _companyFilter = c.id),
                  ),
                ],
              ],
            ),
          ),
        for (final m in shown) _StaffTile(member: m, companyNames: names),
        if (staffCount == 0)
          const Padding(
            padding: EdgeInsets.only(top: Insets.xl),
            child: EmptyState(
              icon: Icons.group_add_outlined,
              title: 'No staff yet',
              message: 'Add staff and choose which companies each person works for.',
            ),
          )
        else if (shown.every((m) => m.isOwner))
          Padding(
            padding: const EdgeInsets.only(top: Insets.xl),
            child: EmptyState(
              icon: Icons.person_search_outlined,
              title: 'Nobody works for ${names[_companyFilter] ?? 'this company'} yet',
              message: 'Open a staff member and use "Change companies" to assign them.',
            ),
          ),
      ],
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({required this.member, required this.companyNames});

  final StaffMember member;
  final Map<String, String> companyNames;

  @override
  Widget build(BuildContext context) {
    final muted = !member.isActive;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: member.isOwner ? context.colors.primaryContainer : context.colors.secondaryContainer,
        foregroundColor: member.isOwner ? context.colors.onPrimaryContainer : context.colors.onSecondaryContainer,
        child: Text(member.displayName.characters.first.toUpperCase()),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              member.displayName,
              overflow: TextOverflow.ellipsis,
              style: muted ? TextStyle(color: context.colors.onSurfaceVariant) : null,
            ),
          ),
          const SizedBox(width: Insets.s),
          _Badge(label: member.isOwner ? 'Owner' : 'Staff', color: context.colors.surfaceContainerHighest),
          if (muted) ...[
            const SizedBox(width: Insets.xs),
            _Badge(label: 'Disabled', color: context.colors.errorContainer, textColor: context.colors.onErrorContainer),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (member.email != null) Text(member.email!, overflow: TextOverflow.ellipsis),
          if (member.isOwner)
            const Text('All companies')
          else if (member.hasNoCompany)
            Padding(
              padding: const EdgeInsets.only(top: Insets.xs),
              child: _Badge(
                label: 'No company',
                icon: Icons.warning_amber_rounded,
                color: context.semantic.warningContainer,
                textColor: context.semantic.onWarningContainer,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: Insets.xs),
              child: Wrap(
                spacing: Insets.xs,
                runSpacing: Insets.xs,
                children: [
                  for (final a in member.companies)
                    _Badge(label: companyNames[a.companyId] ?? 'Company', color: context.colors.secondaryContainer),
                ],
              ),
            ),
        ],
      ),
      isThreeLine: true,
      onTap: () => context.push('/staff/${member.id}'),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, this.textColor, this.icon});

  final String label;
  final Color color;
  final Color? textColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = textColor ?? context.colors.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.s, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Insets.s)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: Insets.xs)],
          Flexible(
            child: Text(
              label,
              style: context.text.labelSmall?.copyWith(color: fg),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
