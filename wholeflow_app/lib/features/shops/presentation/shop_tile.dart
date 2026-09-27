import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/widgets/balance_text.dart';
import '../../../core/widgets/states.dart';
import '../domain/shop.dart';

class ShopTile extends StatelessWidget {
  const ShopTile({super.key, required this.shop, this.showArea = true});

  final ShopSummary shop;
  final bool showArea;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (showArea) areaLabel(shop.area),
      if (shop.phone != null && shop.phone!.trim().isNotEmpty) shop.phone!.trim(),
    ].join(' · ');
    return ListTile(
      title: Text(shop.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.42),
        child: BalanceText(shop.receivable, textAlign: TextAlign.end),
      ),
      onTap: () {
        dismissKeyboard();
        context.push('/shop/${shop.id}');
      },
    );
  }
}
