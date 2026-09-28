import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../domain/stock_item.dart';

extension StockStatusColor on StockStatus {
  /// Always shown next to the status label, never on its own.
  Color color(BuildContext context) => switch (this) {
    StockStatus.inStock => context.semantic.credit,
    StockStatus.low => context.semantic.warning,
    StockStatus.zero => context.colors.onSurfaceVariant,
    StockStatus.negative => context.semantic.owed,
  };
}

/// Small coloured status label, e.g. "Low stock".
class StockStatusLabel extends StatelessWidget {
  const StockStatusLabel(this.status, {super.key, this.style});

  final StockStatus status;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      status.label,
      style: (style ?? context.text.labelMedium)?.copyWith(color: status.color(context)),
      maxLines: 1,
    );
  }
}

class StockItemTile extends StatelessWidget {
  const StockItemTile({super.key, required this.item});

  final StockItem item;

  @override
  Widget build(BuildContext context) {
    final subtitle = [if (item.aliases.isNotEmpty) item.aliases.first, groupLabel(item.group)].join(' · ');
    final value = item.closingValue;
    return ListTile(
      title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatQty(item.closingQty, item.unit),
              style: context.text.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.status != StockStatus.inStock)
              StockStatusLabel(item.status)
            else if (value != null)
              Text(
                formatInrCompact(value),
                style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant),
                maxLines: 1,
              ),
          ],
        ),
      ),
      onTap: () {
        dismissKeyboard();
        context.push('/stock/item/${item.id}');
      },
    );
  }
}

/// Label/value row used on the detail screens.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueStyle});

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
          ),
          const SizedBox(width: Insets.m),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: (valueStyle ?? context.text.bodyMedium)?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Outlined card with a title, used to group detail rows.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Insets.s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.l, Insets.l, Insets.l, Insets.xs),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: context.text.titleMedium)),
                  ?trailing,
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// `₹1,250.00 / Nos`.
String formatRate(Money rate, String? unit) {
  final u = unit?.trim() ?? '';
  return u.isEmpty ? formatInr(rate) : '${formatInr(rate)} / $u';
}
