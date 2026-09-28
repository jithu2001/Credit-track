import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';

/// What the business owes a supplier: `₹1,200.00 Cr` (you owe) /
/// `₹50.00 Dr` (advance paid) / `Settled`. The side is always spelled out.
class PayableText extends StatelessWidget {
  const PayableText(this.payable, {super.key, this.style, this.compact = false, this.textAlign});

  /// Positive = the business owes the supplier.
  final Money payable;
  final TextStyle? style;
  final bool compact;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final owed = payable.isPositive;
    final color = payable.isZero
        ? context.colors.onSurfaceVariant
        : owed
        ? context.semantic.owed
        : context.semantic.credit;
    final amount = compact ? formatInrCompact(payable.abs()) : formatInr(payable.abs());
    final text = payable.isZero ? 'Settled' : '$amount ${owed ? 'Cr' : 'Dr'}';
    final spoken = payable.isZero
        ? 'settled'
        : owed
        ? 'you owe ${formatInr(payable.abs())}'
        : 'advance paid ${formatInr(payable.abs())}';
    final base = (style ?? context.text.titleSmall)!.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]);
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Text(text, style: base, textAlign: textAlign),
    );
  }
}
