import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/core/providers.dart';
import 'package:wholeflow_app/features/auth/domain/app_user.dart';
import 'package:wholeflow_app/features/auth/presentation/session_controller.dart';
import 'package:wholeflow_app/features/company/data/company_repository.dart';
import 'package:wholeflow_app/features/company/domain/company.dart';
import 'package:wholeflow_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:wholeflow_app/features/inventory/presentation/inventory_providers.dart';
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
      const StockItem(id: 'i2', name: 'TUBE 12', unit: 'Nos', closingQty: 2, reorderLevel: 10),
    ];
  }

  @override
  Future<StockItem> item(String itemId, {required bool withCosts}) async => throw UnimplementedError();
  @override
  Future<List<ItemPurchase>> purchasesOf(String itemId, {int limit = 20}) async => const [];
  @override
  Future<Map<String, double>> minimums(String companyId) async => const {};
  @override
  Future<void> setMinimum(String companyId, Iterable<String> itemIds, double? min) async {}
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

Future<List<Override>> overrides(AppUser user, InventoryRepository inventory) async {
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

  group('minimum stock', () {
    testWidgets('owner long-presses, selects all shown, and sets one minimum for all', (tester) async {
      final inventory = _MinimumRepository([
        const StockItem(id: 'a', name: 'TYRE A', unit: 'Nos', closingQty: 40),
        const StockItem(id: 'b', name: 'TYRE B', unit: 'Nos', closingQty: 5),
        const StockItem(id: 'c', name: 'OIL 1L', unit: 'Ltr', closingQty: 12),
      ]);
      await pumpScreen(tester, const StockScreen(), overrides: await overrides(owner, inventory));
      await tester.pumpAndSettle();
      expect(find.textContaining('Long-press items to set minimum stock'), findsOneWidget);

      await tester.longPress(find.text('TYRE A'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Select all shown'));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);

      await tester.tap(find.byKey(const Key('set-minimum')));
      await tester.pumpAndSettle();
      expect(find.text('Minimum for 3 items'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('minimum-field')), '20');
      await tester.tap(find.byKey(const Key('minimum-save')));
      await tester.pumpAndSettle();

      expect(inventory.calls, hasLength(1));
      expect(inventory.calls.single.ids, {'a', 'b', 'c'});
      expect(inventory.calls.single.min, 20);
      // Reloaded with the new minimums: TYRE B (5) and OIL (12) are now low.
      expect(find.text('Low stock (2)'), findsOneWidget);
      expect(find.textContaining('Min 20 Nos'), findsNWidgets(2));
      expect(find.text('3 selected'), findsNothing, reason: 'selection ends after saving');
    });

    testWidgets('staff cannot start selecting', (tester) async {
      final inventory = _MinimumRepository([const StockItem(id: 'a', name: 'TYRE A', closingQty: 4, minQty: 10)]);
      await pumpRoutedScreen(tester, const StockScreen(), overrides: await overrides(staffUser, inventory));
      await tester.pumpAndSettle();
      expect(find.text('Low stock (1)'), findsOneWidget, reason: 'staff still see the alert status');
      expect(find.textContaining('Long-press'), findsNothing);
      await tester.longPress(find.text('TYRE A'));
      await tester.pumpAndSettle();
      expect(find.textContaining('selected'), findsNothing);
      expect(find.byKey(const Key('set-minimum')), findsNothing);
    });

    testWidgets('dashboard stock alert lists the furthest below and opens the low-stock list', (tester) async {
      final inventory = _MinimumRepository([
        const StockItem(id: 'a', name: 'TYRE A', unit: 'Nos', closingQty: 9, minQty: 10),
        const StockItem(id: 'b', name: 'TUBE', unit: 'Nos', closingQty: 0, minQty: 4),
        const StockItem(id: 'c', name: 'OIL', unit: 'Ltr', closingQty: 50, minQty: 10),
        const StockItem(id: 'd', name: 'BELT', unit: 'Nos', closingQty: 2, reorderLevel: 6),
      ]);
      await pumpRoutedScreen(
        tester,
        const Scaffold(body: StockAlertCard(companyId: 'co-a')),
        overrides: await overrides(owner, inventory),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 items at or below minimum'), findsOneWidget);
      final lines = tester.widgetList<Text>(
        find.descendant(of: find.byKey(const Key('stock-alert')), matching: find.byType(Text)),
      );
      final texts = lines.map((t) => t.data).whereType<String>().toList();
      expect(texts.indexWhere((t) => t.startsWith('TUBE')), lessThan(texts.indexWhere((t) => t.startsWith('BELT'))));
      expect(texts.indexWhere((t) => t.startsWith('BELT')), lessThan(texts.indexWhere((t) => t.startsWith('TYRE A'))));
      expect(find.textContaining('OIL'), findsNothing);

      await tester.tap(find.byKey(const Key('stock-alert')));
      await tester.pumpAndSettle();
      expect(find.text('at /stock'), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.text('at /stock')));
      expect(container.read(inventoryBelowMinimumProvider), isTrue);
      expect(container.read(inventoryStatusFilterProvider), isNull);
    });

    testWidgets('below minimum shows the same items as the dashboard, out of stock included', (tester) async {
      final inventory = _MinimumRepository([
        const StockItem(id: 'a', name: 'TYRE A', unit: 'Nos', closingQty: 9, minQty: 10),
        const StockItem(id: 'b', name: 'TUBE', unit: 'Nos', closingQty: 0, minQty: 4),
        const StockItem(id: 'c', name: 'OIL', unit: 'Ltr', closingQty: 50, minQty: 10),
        const StockItem(id: 'e', name: 'CHAIN', unit: 'Nos', closingQty: 0),
      ]);
      await pumpRoutedScreen(tester, const StockScreen(), overrides: await overrides(owner, inventory));
      await tester.pumpAndSettle();
      expect(find.text('Below minimum (2)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('below-minimum')));
      await tester.pumpAndSettle();
      expect(find.text('TYRE A'), findsOneWidget);
      expect(find.text('TUBE'), findsOneWidget);
      expect(find.text('OIL'), findsNothing);
      expect(find.text('CHAIN'), findsNothing, reason: 'out of stock but no minimum');
    });

    testWidgets('no below-minimum chip while no item has a minimum', (tester) async {
      final inventory = _MinimumRepository([const StockItem(id: 'a', name: 'TYRE A', closingQty: 0)]);
      await pumpRoutedScreen(tester, const StockScreen(), overrides: await overrides(owner, inventory));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('below-minimum')), findsNothing);
    });

    testWidgets('dashboard card stays hidden while no item has a minimum', (tester) async {
      final inventory = _MinimumRepository([const StockItem(id: 'a', name: 'TYRE A', closingQty: 0)]);
      await pumpScreen(
        tester,
        const Scaffold(body: StockAlertCard(companyId: 'co-a')),
        overrides: await overrides(owner, inventory),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stock-alert')), findsNothing);
    });
  });
}

/// Items in memory; setMinimum records the call and updates the items.
class _MinimumRepository implements InventoryRepository {
  _MinimumRepository(this.list);

  List<StockItem> list;
  final List<({Set<String> ids, double? min})> calls = [];

  @override
  Future<List<StockItem>> items(String companyId, {required bool withCosts}) async => list;
  @override
  Future<StockItem> item(String itemId, {required bool withCosts}) async => list.firstWhere((i) => i.id == itemId);
  @override
  Future<List<ItemPurchase>> purchasesOf(String itemId, {int limit = 20}) async => const [];
  @override
  Future<Map<String, double>> minimums(String companyId) async => {
    for (final i in list)
      if (i.minQty != null) i.id: i.minQty!,
  };
  @override
  Future<void> setMinimum(String companyId, Iterable<String> itemIds, double? min) async {
    final ids = itemIds.toSet();
    calls.add((ids: ids, min: min));
    list = [for (final i in list) ids.contains(i.id) ? i.withMinimum(min) : i];
  }
}
