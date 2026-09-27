import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/payment_analysis.dart';
import 'analytics_providers.dart';

String formatDays(double? d) => d == null ? '—' : plural(d.round(), 'day');
String formatPercent(double? r) => r == null ? '—' : '${(r * 100).round()}%';

/// "Credit period: 15 · 30 · 45 · 60 · 90 · Custom" filter chips.
class CreditDaysFilter extends ConsumerWidget {
  const CreditDaysFilter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(creditDaysProvider);
    final custom = !creditDayPresets.contains(days);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.l),
          child: Text('Credit period', style: context.text.labelLarge),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.s),
            children: [
              for (final d in creditDayPresets) ...[
                ChoiceChip(
                  label: Text('$d days'),
                  selected: days == d,
                  onSelected: (_) => ref.read(creditDaysProvider.notifier).set(d),
                ),
                const SizedBox(width: Insets.s),
              ],
              ChoiceChip(
                avatar: const Icon(Icons.edit_outlined, size: 18),
                label: Text(custom ? '$days days' : 'Custom'),
                selected: custom,
                onSelected: (_) => _askCustom(context, ref, days),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _askCustom(BuildContext context, WidgetRef ref, int current) async {
    final controller = TextEditingController(text: '$current');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Credit period'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
          decoration: const InputDecoration(labelText: 'Days allowed to pay', suffixText: 'days'),
          onSubmitted: (v) => Navigator.pop(context, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, int.tryParse(controller.text)), child: const Text('Apply')),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value > 0) ref.read(creditDaysProvider.notifier).set(value);
  }
}

/// Status with icon + label (never colour alone).
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final s = context.semantic;
    final (icon, bg, fg) = switch (status) {
      PaymentStatus.onTrack => (Icons.check_circle_outline, s.creditContainer, s.onCreditContainer),
      PaymentStatus.slightlyLate => (Icons.schedule, s.warningContainer, s.onWarningContainer),
      PaymentStatus.late => (Icons.warning_amber_rounded, s.warningContainer, s.onWarningContainer),
      PaymentStatus.veryLate => (Icons.error_outline, s.owedContainer, s.onOwedContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.s, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Insets.s)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: Insets.xs),
          Text(status.label, style: context.text.labelSmall?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// Open dues by age: one row per bucket, bar length ∝ amount, amount as text.
/// "Not due" is neutral; late buckets use one hue that darkens with age.
class AgeingBars extends StatelessWidget {
  const AgeingBars({super.key, required this.ageing});

  final Map<AgeBucket, Money> ageing;

  @override
  Widget build(BuildContext context) {
    final maxPaise = ageing.values.fold(0, (m, v) => v.paise > m ? v.paise : m);
    final owed = context.semantic.owed;
    final surface = context.colors.surfaceContainerLow;
    Color colorFor(AgeBucket b) => switch (b) {
      AgeBucket.notDue => context.colors.outline,
      AgeBucket.d1to30 => Color.lerp(surface, owed, 0.45)!,
      AgeBucket.d31to60 => Color.lerp(surface, owed, 0.65)!,
      AgeBucket.d61to90 => Color.lerp(surface, owed, 0.82)!,
      AgeBucket.d90plus => owed,
    };
    return Column(
      children: [
        for (final b in AgeBucket.values)
          Semantics(
            label: '${b.label}: ${formatInr(ageing[b]!)}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(b.label, style: context.text.bodyMedium)),
                      Text(
                        formatInr(ageing[b]!),
                        style: context.text.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                  const SizedBox(height: Insets.xs),
                  LayoutBuilder(
                    builder: (context, c) {
                      final v = ageing[b]!.paise;
                      final w = maxPaise == 0 ? 0.0 : c.maxWidth * v / maxPaise;
                      return Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: context.colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: v > 0 && w < 4 ? 4 : w,
                          decoration: BoxDecoration(color: colorFor(b), borderRadius: BorderRadius.circular(4)),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value, this.detail, this.background, this.foreground});

  final String label;
  final String value;
  final String? detail;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? context.colors.onSurface;
    return Semantics(
      container: true,
      label: '$label: $value${detail == null ? '' : ', $detail'}',
      excludeSemantics: true,
      child: Card.filled(
        color: background ?? context.colors.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(Insets.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.text.labelLarge?.copyWith(color: fg)),
              const SizedBox(height: Insets.s),
              Text(
                value,
                style: context.text.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
              ),
              if (detail != null) ...[
                const SizedBox(height: Insets.xs),
                Text(detail!, style: context.text.bodySmall?.copyWith(color: fg), maxLines: 2),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
