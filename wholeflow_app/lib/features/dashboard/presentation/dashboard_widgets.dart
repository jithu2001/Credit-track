import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';

enum StatTone { neutral, owed }

class StatData {
  const StatData(this.label, this.value, this.detail, {this.tone = StatTone.neutral});

  final String label;
  final String value;
  final String detail;
  final StatTone tone;
}

class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.tiles});

  /// Null while loading.
  final List<StatData>? tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Four tiles: 2×2 on phones, one row on tablets. Three tiles (staff
        // without transactions): the first spans the phone width.
        final count = tiles?.length ?? 4;
        final full = constraints.maxWidth;
        final columns = full >= 720 ? count : 2;
        final cell = (full - Insets.m * (columns - 1)) / columns;
        return Wrap(
          spacing: Insets.m,
          runSpacing: Insets.m,
          children: [
            for (var i = 0; i < count; i++)
              SizedBox(
                width: columns == 2 && count.isOdd && i == 0 ? full : cell,
                child: tiles == null ? const StatCardSkeleton() : StatCard(tiles![i]),
              ),
          ],
        );
      },
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard(this.stat, {super.key});

  final StatData stat;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final (bg, fg) = switch (stat.tone) {
      StatTone.owed => (semantic.owedContainer, semantic.onOwedContainer),
      StatTone.neutral => (context.colors.surfaceContainerHigh, context.colors.onSurface),
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

class StatCardSkeleton extends StatelessWidget {
  const StatCardSkeleton({super.key});

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
