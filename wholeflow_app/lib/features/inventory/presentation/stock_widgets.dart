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
    return Text(status.label, style: (style ?? context.text.labelMedium)?.copyWith(color: status.color(context)), maxLines: 1);
  }
}

class StockItemTile extends StatelessWidget {
  const StockItemTile({super.key, required this.item, this.selected, this.onSelect, this.onLongPress});

  final StockItem item;

  /// Non-null in selection mode: the tile shows a checkbox and taps toggle it.
  final bool? selected;
  final VoidCallback? onSelect;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (item.aliases.isNotEmpty) item.aliases.first,
      groupLabel(item.group),
      if (item.hasMinimum) 'Min ${formatQty(item.effectiveMin, item.unit)}',
    ].join(' · ');
    final value = item.closingValue;
    final selecting = selected != null;
    return ListTile(
      selected: selected ?? false,
      leading: selecting ? Checkbox(value: selected, onChanged: (_) => onSelect?.call()) : null,
      onLongPress: onLongPress,
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
      onTap: selecting
          ? onSelect
          : () {
              dismissKeyboard();
              context.push('/stock/item/${item.id}');
            },
    );
  }
}

/// The minimum chosen in [askMinimum]: [min] null means "remove the minimum".
typedef MinimumChoice = ({double? min});

/// Bottom sheet asking for a minimum stock quantity, for one item or many.
/// Returns null when cancelled.
Future<MinimumChoice?> askMinimum(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? unit,
  double? current,
  bool canRemove = false,
}) {
  return showModalBottomSheet<MinimumChoice>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _MinimumSheet(title: title, subtitle: subtitle, unit: unit, current: current, canRemove: canRemove),
  );
}

class _MinimumSheet extends StatefulWidget {
  const _MinimumSheet({required this.title, this.subtitle, this.unit, this.current, required this.canRemove});

  final String title;
  final String? subtitle;
  final String? unit;
  final double? current;
  final bool canRemove;

  @override
  State<_MinimumSheet> createState() => _MinimumSheetState();
}

class _MinimumSheetState extends State<_MinimumSheet> {
  late final _value = TextEditingController(text: widget.current == null ? '' : formatQty(widget.current!).replaceAll(',', ''));
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _save() {
    final v = double.tryParse(_value.text.trim().replaceAll(',', ''));
    if (v == null || v <= 0 || v > 999999999) {
      setState(() => _error = 'Enter a quantity above 0');
      return;
    }
    Navigator.of(context).pop((min: v));
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit?.trim() ?? '';
    return Padding(
      padding: EdgeInsets.fromLTRB(Insets.xl, 0, Insets.xl, Insets.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: context.text.titleLarge),
          if (widget.subtitle != null) ...[
            const SizedBox(height: Insets.xs),
            Text(widget.subtitle!, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
          ],
          const SizedBox(height: Insets.l),
          TextField(
            key: const Key('minimum-field'),
            controller: _value,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Minimum stock',
              suffixText: unit.isEmpty ? null : unit,
              errorText: _error,
              helperText: 'You get a stock alert when the quantity is at or below this.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: Insets.l),
          Row(
            children: [
              if (widget.canRemove)
                TextButton(
                  key: const Key('minimum-remove'),
                  onPressed: () => Navigator.of(context).pop((min: null)),
                  child: const Text('Remove minimum'),
                ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              const SizedBox(width: Insets.s),
              FilledButton(key: const Key('minimum-save'), onPressed: _save, child: const Text('Save')),
            ],
          ),
        ],
      ),
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
