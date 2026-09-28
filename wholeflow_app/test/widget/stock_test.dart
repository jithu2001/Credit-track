import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/core/providers.dart';
import 'package:wholeflow_app/features/auth/domain/app_user.dart';
import 'package:wholeflow_app/features/auth/presentation/session_controller.dart';
import 'package:wholeflow_app/features/company/data/company_repository.dart';
import 'package:wholeflow_app/features/company/domain/company.dart';
import 'package:wholeflow_app/features/inventory/data/inventory_repository.dart';
import 'package:wholeflow_app/features/inventory/domain/stock_item.dart';
import 'package:wholeflow_app/features/purchases/data/purchase_repository.dart';
import 'package:wholeflow_app/features/purchases/domain/purchase.dart';
import 'package:wholeflow_app/features/stock/stock_screen.dart';
import 'package:wholeflow_app/features/suppliers/data/supplier_repository.dart';
import 'package:wholeflow_app/features/suppliers/domain/supplier.dart';

import 'helpers.dart';

const companyA = Company(id: 'co-a', companyName: 'JMJ Marketing', syncStatus: 'SYNCED');

class FakeInventoryRepository implements InventoryRepository {
  final List<bool> requestedWithCosts = [];

  @override
  Future<List<StockItem>> items(String companyId, {required bool withCosts}) async {
    requestedWithCosts.add(withCosts);
    return [
      StockItem(
        id: 'i1',
        name: 'TYRE 145/80 R12',
        unit: 'Nos',
        closingQty: 1250,
        closingValue: withCosts ? const Money(15000000) : null,
      ),
      const StockItem(id: 'i2', name: 'TUBE 12', unit: 'Nos', closingQty: 2, status: StockStatus.low),
    ];
  }

  @override
  Future<StockItem> item(String itemId, {required bool withCosts}) async => throw UnimplementedError();
  @override
  Future<List<ItemPurchase>> purchasesOf(String itemId, {int limit = 20}) async => const [];
}

class FakePurchaseRepository implements PurchaseRepository {
  @override
  Future<List<PurchaseSummary>> page(PurchaseQuery query, int pageIndex) async => pageIndex > 0
      ? const []
      : [PurchaseSummary(id: 'p1', date: DateTime(2026, 9, 15), supplierName: 'MRF LTD', total: const Money(117960))];
  @override
  Future<PurchaseDetail> detail(String purchaseId) async => throw UnimplementedError();
  @override
  Future<List<MonthPurchases>> monthTotals(String companyId, DateTime from, {String? supplierId}) async => const [];
}

class FakeSupplierRepository implements SupplierRepository {
  @override
  Future<List<Supplier>> all(String companyId) async => const [
    Supplier(id: 's1', companyId: 'co-a', name: 'MRF LTD', payable: Money(5000000)),
  ];
  @override
  Future<Supplier> detail(String supplierId) async => throw UnimplementedError();
}

Future<List<Override>> overrides(AppUser user, FakeInventoryRepository inventory) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    currentUserProvider.overrideWithValue(user),
    companyRepositoryProvider.overrideWithValue(
      FakeCompanyRepository(
        companies: const [companyA],
        access: const [CompanyAccess(userId: 'staff-1', companyId: 'co-a')],
      ),
    ),
    inventoryRepositoryProvider.overrideWithValue(inventory),
    purchaseRepositoryProvider.overrideWithValue(FakePurchaseRepository()),
    supplierRepositoryProvider.overrideWithValue(FakeSupplierRepository()),
  ];
}

void main() {
  testWidgets('owner gets Inventory, Purchases and Suppliers with stock values', (tester) async {
    final inventory = FakeInventoryRepository();
    await pumpScreen(tester, const StockScreen(), overrides: await overrides(owner, inventory));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Tab, 'Inventory'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Purchases'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Suppliers'), findsOneWidget);
    expect(inventory.requestedWithCosts, [true]);
    expect(find.text('1,250 Nos'), findsOneWidget);
    expect(find.text('Low stock'), findsOneWidget);
    expect(find.textContaining('Value ₹1.5 L'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Purchases'));
    await tester.pumpAndSettle();
    expect(find.text('MRF LTD'), findsOneWidget);
    expect(find.text('₹1,179.60'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Suppliers'));
    await tester.pumpAndSettle();
    expect(find.text('₹50,000.00 Cr'), findsOneWidget);
  });

  testWidgets('staff see only inventory, loaded without costs', (tester) async {
    final inventory = FakeInventoryRepository();
    await pumpScreen(tester, const StockScreen(), overrides: await overrides(staffUser, inventory));
    await tester.pumpAndSettle();

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Purchases'), findsNothing);
    expect(find.text('Suppliers'), findsNothing);
    expect(find.text('Inventory'), findsOneWidget);
    expect(inventory.requestedWithCosts, [false]);
    expect(find.text('1,250 Nos'), findsOneWidget);
    expect(find.textContaining('Value'), findsNothing);
  });
}
