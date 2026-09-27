import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../company/domain/company.dart';
import '../domain/dashboard_models.dart';
import 'dashboard_providers.dart';

/// "Updated 4 min ago", or a warning when the figures may be stale.
class FreshnessBanner extends ConsumerWidget {
  const FreshnessBanner({super.key, required this.company});

  final Company company;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companySyncStateProvider(company.id));
    if (!state.hasValue && state.isLoading) return const SizedBox(height: 56);
    final freshness = evaluateFreshness(state: state.value, companySyncStatus: company.syncStatus, now: DateTime.now());
    final warning = freshness.level == FreshnessLevel.warning;
    final semantic = context.semantic;
    final bg = warning ? semantic.warningContainer : context.colors.surfaceContainerHigh;
    final fg = warning ? semantic.onWarningContainer : context.colors.onSurfaceVariant;
    return Semantics(
      container: true,
      liveRegion: warning,
      child: Card.filled(
        color: bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.m),
          child: Row(
            children: [
              Icon(warning ? Icons.warning_amber_rounded : Icons.cloud_done_outlined, color: fg),
              const SizedBox(width: Insets.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(freshness.headline, style: context.text.bodyMedium?.copyWith(color: fg)),
                    if (freshness.detail != null) Text(freshness.detail!, style: context.text.bodySmall?.copyWith(color: fg)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
