import 'package:flutter/material.dart';

import '../money/money.dart';
import '../theme/app_theme.dart';

/// A signed balance shown as `₹1,200.00 Dr` / `₹50.00 Cr` / `Settled`.
/// The side is always spelled out, so colour is never the only signal.
class BalanceText extends StatelessWidget {
  const BalanceText(this.amount, {super.key, this.style, this.compact = false, this.textAlign});

  final Money amount;
  final TextStyle? style;
  final bool compact;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final side = amount.side;
    final color = switch (side) {
      BalanceSide.dr => semantic.owed,
      BalanceSide.cr => semantic.credit,
      null => context.colors.onSurfaceVariant,
    };
    final base = (style ?? context.text.titleSmall)!.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]);
    final text = side == null ? 'Settled' : '${compact ? formatInrCompact(amount.abs()) : formatInr(amount.abs())} ${side.label}';
    final spoken = switch (side) {
      BalanceSide.dr => 'owes ${formatInr(amount.abs())}',
      BalanceSide.cr => 'in credit ${formatInr(amount.abs())}',
      null => 'settled',
    };
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Text(text, style: base, textAlign: textAlign),
    );
  }
}
