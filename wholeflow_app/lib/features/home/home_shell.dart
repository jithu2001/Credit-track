import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/states.dart';
import '../auth/domain/app_user.dart';
import '../auth/presentation/session_controller.dart';
import '../company/presentation/company_providers.dart';
import '../shops/presentation/shop_list_controller.dart';
import 'refresh.dart';

/// Shell branch indices, in router order.
abstract final class Branch {
  static const dashboard = 0;
  static const shops = 1;
  static const outstanding = 2;
  static const staff = 3;
  static const settings = 4;
}

class NavItem {
  const NavItem(this.branch, this.label, this.icon, this.selectedIcon);

  final int branch;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// The navigation destinations a role gets. Staff never see the Staff tab.
List<NavItem> navItemsFor(UserRole role) => [
  const NavItem(Branch.dashboard, 'Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  const NavItem(Branch.shops, 'Shops', Icons.storefront_outlined, Icons.storefront_rounded),
  const NavItem(Branch.outstanding, 'Outstanding', Icons.request_quote_outlined, Icons.request_quote_rounded),
  if (role == UserRole.owner) const NavItem(Branch.staff, 'Staff', Icons.group_outlined, Icons.group_rounded),
  const NavItem(Branch.settings, 'Settings', Icons.settings_outlined, Icons.settings_rounded),
];

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(refreshCompanyData(ref)));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Area filters belong to a company: drop them when the company changes.
    ref.listen(activeCompanyProvider.select((c) => c.value?.id), (prev, next) {
      if (prev != null && prev != next) ref.read(shopFilterControllerProvider.notifier).setAreas(const {});
    });

    final user = ref.watch(currentUserProvider);
    if (user == null) return const Scaffold();
    final companies = ref.watch(companiesProvider);
    final shell = widget.navigationShell;
    final items = navItemsFor(user.role);
    // Settings stays reachable even without a company, so users can sign out.
    final onSettings = shell.currentIndex == Branch.settings;

    final Widget body = switch (companies) {
      _ when onSettings => shell,
      AsyncValue(:final value?) when value.isEmpty => NoCompanyView(isOwner: user.isOwner),
      AsyncValue(:final value?) when value.isNotEmpty => shell,
      AsyncValue(:final error?) => Scaffold(
        body: SafeArea(
          child: ErrorState(error: error, onRetry: () => refreshCompanyData(ref)),
        ),
      ),
      _ => const Scaffold(body: SafeArea(child: SkeletonList())),
    };

    final selected = items.indexWhere((i) => i.branch == shell.currentIndex).clamp(0, items.length - 1);
    void go(int index) {
      final branch = items[index].branch;
      shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
    }

    final wide = MediaQuery.sizeOf(context).width >= Insets.railBreakpoint;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              right: false,
              child: NavigationRail(
                selectedIndex: selected,
                onDestinationSelected: go,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final i in items)
                    NavigationRailDestination(icon: Icon(i.icon), selectedIcon: Icon(i.selectedIcon), label: Text(i.label)),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: go,
        destinations: [
          for (final i in items) NavigationDestination(icon: Icon(i.icon), selectedIcon: Icon(i.selectedIcon), label: i.label),
        ],
      ),
    );
  }
}

/// A staff member without assigned companies (or an owner before the first sync).
class NoCompanyView extends ConsumerWidget {
  const NoCompanyView({super.key, required this.isOwner});

  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('WholeFlow')),
      body: RefreshIndicator(
        onRefresh: () => refreshCompanyData(ref),
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: c.maxHeight,
              child: EmptyState(
                key: const Key('no-company'),
                icon: Icons.domain_disabled_outlined,
                title: isOwner ? 'No companies synced yet' : "You haven't been assigned to any company yet",
                message: isOwner
                    ? 'Companies appear here after the WholeFlow sync service on the Tally PC runs for the first time.'
                    : 'Ask your business owner to assign you to a company.',
                action: Wrap(
                  spacing: Insets.s,
                  runSpacing: Insets.s,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => refreshCompanyData(ref),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Check again'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
