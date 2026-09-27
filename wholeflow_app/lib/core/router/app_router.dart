import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/analytics/presentation/analytics_screen.dart';
import '../../features/analytics/presentation/shop_payments_screen.dart';
import '../../features/auth/presentation/auth_screens.dart';
import '../../features/auth/presentation/session_controller.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/outstanding/presentation/outstanding_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shop_detail/presentation/shop_detail_screen.dart';
import '../../features/shops/presentation/shops_screen.dart';
import '../../features/staff/presentation/staff_detail_screen.dart';
import '../../features/staff/presentation/staff_form_screen.dart';
import '../../features/staff/presentation/staff_list_screen.dart';
import '../../features/sync_health/presentation/sync_health_screen.dart';

part 'app_router.g.dart';

const _authRoutes = {'/splash', '/login', '/change-password'};

/// Where the router should send the user, given the session; null = stay.
@visibleForTesting
String? redirectFor(AsyncValue<Session> session, String location) {
  if (!session.hasValue) return location == '/splash' ? null : '/splash';
  final s = session.value!;
  switch (s) {
    case SignedOut():
      return location == '/login' ? null : '/login';
    case SignedIn(:final user, :final mustChangePassword):
      if (mustChangePassword) return location == '/change-password' ? null : '/change-password';
      if (_authRoutes.contains(location)) return '/dashboard';
      final ownerOnly = location.startsWith('/staff') || location.startsWith('/sync-health') || location.startsWith('/analytics');
      if (ownerOnly && !user.isOwner) return '/dashboard';
      return null;
  }
}

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final refresh = ValueNotifier(0);
  ref
    ..listen(sessionControllerProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(ref.read(sessionControllerProvider), state.matchedLocation),
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/change-password', builder: (context, state) => const ForcePasswordChangeScreen()),
      GoRoute(
        path: '/shop/:id',
        builder: (context, state) => ShopDetailScreen(shopId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/staff/new', builder: (context, state) => const StaffFormScreen()),
      GoRoute(
        path: '/staff/:id',
        builder: (context, state) => StaffDetailScreen(userId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/staff/:id/edit',
        builder: (context, state) => StaffFormScreen(userId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/sync-health', builder: (context, state) => const SyncHealthScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      GoRoute(
        path: '/analytics/shop/:id',
        builder: (context, state) => ShopPaymentsScreen(shopId: state.pathParameters['id']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/shops', builder: (context, state) => const ShopsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/outstanding', builder: (context, state) => const OutstandingScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/analytics', builder: (context, state) => const AnalyticsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/staff', builder: (context, state) => const StaffListScreen())],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}
