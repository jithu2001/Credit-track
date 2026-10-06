import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/presentation/session_controller.dart';
import '../company/presentation/company_providers.dart';
import '../company/presentation/company_switcher.dart';
import '../home/account_button.dart';
import '../inventory/presentation/inventory_providers.dart';
import '../inventory/presentation/inventory_view.dart';
import '../purchases/presentation/purchase_list_view.dart';
import '../suppliers/presentation/supplier_list_view.dart';

/// The Stock tab. Owners get Inventory, Purchases and Suppliers; staff get
/// Inventory only (RLS returns purchases and suppliers to the owner alone).
class StockScreen extends ConsumerWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final company = ref.watch(activeCompanyProvider).value;
    if (user == null) return const Scaffold();
    // Keyed by company so search and filters start fresh after a switch.
    final inventory = company == null
        ? const SizedBox.shrink()
        : InventoryView(key: ValueKey('inventory-${company.id}'), companyId: company.id);

    if (!user.isOwner) {
      return Scaffold(
        appBar: AppBar(
          title: const CompanyTitle(screen: 'Inventory'),
          actions: const [AccountButton()],
        ),
        body: inventory,
      );
    }
    return DefaultTabController(
      length: 3,
      child: _ShowInventoryOnFilter(
        child: Scaffold(
          appBar: AppBar(
            title: const CompanyTitle(screen: 'Stock'),
            actions: const [AccountButton()],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Inventory'),
                Tab(text: 'Purchases'),
                Tab(text: 'Suppliers'),
              ],
            ),
          ),
          body: company == null
              ? const SizedBox.shrink()
              : TabBarView(
                  children: [
                    inventory,
                    PurchaseListView(key: ValueKey('purchases-${company.id}'), companyId: company.id),
                    SupplierListView(key: ValueKey('suppliers-${company.id}'), companyId: company.id),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The dashboard's stock alert sets the inventory filter; bring the
/// Inventory tab to the front when that happens.
class _ShowInventoryOnFilter extends ConsumerWidget {
  const _ShowInventoryOnFilter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(inventoryStatusFilterProvider, (_, next) {
      if (next != null) DefaultTabController.of(context).animateTo(0);
    });
    ref.listen(inventoryBelowMinimumProvider, (_, next) {
      if (next) DefaultTabController.of(context).animateTo(0);
    });
    return child;
  }
}
