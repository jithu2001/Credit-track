import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/states.dart';
import '../company/presentation/company_providers.dart';
import '../shops/presentation/shop_list_controller.dart';
import 'home_shell.dart';
import 'refresh.dart';

/// Navigation items for the staff mobile app.
const staffNavItems = [
  NavItem(0, 'Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  NavItem(1, 'Shops', Icons.storefront_outlined, Icons.storefront_rounded),
  NavItem(2, 'Inventory', Icons.inventory_2_outlined, Icons.inventory_2_rounded),
];

class StaffHomeShell extends ConsumerStatefulWidget {
  const StaffHomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<StaffHomeShell> createState() => _StaffHomeShellState();
}

class _StaffHomeShellState extends ConsumerState<StaffHomeShell> {
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
    ref.listen(activeCompanyProvider.select((c) => c.value?.id), (prev, next) {
      if (prev != null && prev != next) ref.read(shopFilterControllerProvider.notifier).setAreas(const {});
    });

    final companies = ref.watch(companiesProvider);
    final shell = widget.navigationShell;
    final Widget body = switch (companies) {
      AsyncValue(:final value?) when value.isEmpty => const NoCompanyView(isOwner: false),
      AsyncValue(:final value?) when value.isNotEmpty => shell,
      AsyncValue(:final error?) => Scaffold(
        body: SafeArea(
          child: ErrorState(error: error, onRetry: () => refreshCompanyData(ref)),
        ),
      ),
      _ => const Scaffold(body: SafeArea(child: SkeletonList())),
    };

    final selected = shell.currentIndex.clamp(0, staffNavItems.length - 1);
    void go(int index) {
      shell.goBranch(index, initialLocation: index == shell.currentIndex);
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
                  for (final i in staffNavItems)
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
          for (final i in staffNavItems)
            NavigationDestination(icon: Icon(i.icon), selectedIcon: Icon(i.selectedIcon), label: i.label),
        ],
      ),
    );
  }
}
