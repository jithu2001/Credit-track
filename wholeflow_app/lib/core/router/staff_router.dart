import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/states.dart';
import '../../features/auth/presentation/auth_screens.dart';
import '../../features/auth/presentation/session_controller.dart';
import '../../features/dashboard/presentation/staff_dashboard_screen.dart';
import '../../features/home/staff_home_shell.dart';
import '../../features/inventory/presentation/staff_inventory_screen.dart';
import '../../features/inventory/presentation/stock_item_screen.dart';
import '../../features/settings/presentation/staff_settings_screen.dart';
import '../../features/shop_detail/presentation/shop_detail_screen.dart';
import '../../features/shops/presentation/shops_screen.dart';
import '../../features/visits/domain/visit.dart';
import '../../features/visits/presentation/check_in_screen.dart';
import '../../features/visits/presentation/staff_visits_screen.dart';
import '../../features/visits/presentation/visit_detail_screen.dart';

part 'staff_router.g.dart';

const _authRoutes = {'/splash', '/login', '/change-password', '/not-staff'};

/// Where the staff router should send the user, given the session; null = stay.
@visibleForTesting
String? staffRedirectFor(AsyncValue<Session> session, String location) {
  if (!session.hasValue) return location == '/splash' ? null : '/splash';
  final s = session.value!;
  switch (s) {
    case SignedOut():
      return location == '/login' ? null : '/login';
    case SignedIn(:final user, :final mustChangePassword):
      if (mustChangePassword) return location == '/change-password' ? null : '/change-password';
      if (user.isOwner) return location == '/not-staff' ? null : '/not-staff';
      if (_authRoutes.contains(location)) return '/dashboard';
      return null;
  }
}

@Riverpod(keepAlive: true)
GoRouter staffRouter(Ref ref) {
  final refresh = ValueNotifier(0);
  ref
    ..listen(sessionControllerProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) => staffRedirectFor(ref.read(sessionControllerProvider), state.matchedLocation),
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/change-password', builder: (context, state) => const ForcePasswordChangeScreen()),
      GoRoute(path: '/not-staff', builder: (context, state) => const NotStaffScreen()),
      GoRoute(
        path: '/shop/:id',
        builder: (context, state) => ShopDetailScreen(shopId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/settings', builder: (context, state) => const StaffSettingsScreen()),
      GoRoute(
        path: '/stock/item/:id',
        builder: (context, state) => StockItemScreen(itemId: state.pathParameters['id']!),
      ),
      // Outstanding is now the Dues and Overdue views of the Shops tab.
      GoRoute(path: '/outstanding', redirect: (context, state) => '/shops'),
      GoRoute(
        path: '/visits/check-in',
        builder: (context, state) => _withTask(state, (t) => CheckInScreen(task: t)),
      ),
      GoRoute(
        path: '/visits/task',
        builder: (context, state) => _withTask(state, (t) => VisitDetailScreen(task: t)),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => StaffHomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/dashboard', builder: (context, state) => const StaffDashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/shops', builder: (context, state) => const ShopsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/inventory', builder: (context, state) => const StaffInventoryScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/visits', builder: (context, state) => const StaffVisitsScreen())],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}

/// Visit screens get their task from the list that opened them; a cold deep
/// link has none, so it goes back to the Visits tab.
Widget _withTask(GoRouterState state, Widget Function(VisitTask) build) {
  final task = state.extra;
  return task is VisitTask ? build(task) : const StaffVisitsScreen();
}

/// Shown when a Business Owner attempts to open the WholeFlow Staff app.
class NotStaffScreen extends ConsumerWidget {
  const NotStaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('WholeFlow Staff')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Insets.xl),
          child: EmptyState(
            icon: Icons.badge_outlined,
            title: 'Staff app',
            message:
                'This app is for Staff. You are signed in with a Business Owner account.\n\n'
                'Please open the WholeFlow Owner app to sign in.',
            action: FilledButton.tonalIcon(
              onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ),
        ),
      ),
    );
  }
}
