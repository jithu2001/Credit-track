import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../company/presentation/company_providers.dart';
import '../../company/presentation/company_switcher.dart';
import '../../home/account_button.dart';
import 'inventory_view.dart';

/// The staff inventory screen. Shows quantities and stock status for the
/// assigned company. Does not load purchase prices, stock values, or suppliers.
class StaffInventoryScreen extends ConsumerWidget {
  const StaffInventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(activeCompanyProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const CompanyTitle(screen: 'Inventory'),
        actions: const [AccountButton()],
      ),
      body: company == null
          ? const SizedBox.shrink()
          : InventoryView(key: ValueKey('inventory-${company.id}'), companyId: company.id),
    );
  }
}
