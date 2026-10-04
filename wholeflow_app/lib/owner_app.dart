import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/owner_router.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/presentation/theme_controller.dart';

class WholeFlowOwnerApp extends ConsumerWidget {
  const WholeFlowOwnerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(ownerRouterProvider);
    final mode = ref.watch(themeControllerProvider);
    return DynamicColorBuilder(
      builder: (light, dark) => MaterialApp.router(
        title: 'WholeFlow Owner',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(light),
        darkTheme: AppTheme.dark(dark),
        themeMode: mode,
        routerConfig: router,
      ),
    );
  }
}
