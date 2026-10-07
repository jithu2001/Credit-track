import 'package:flutter_test/flutter_test.dart';
import 'package:wholeflow_app/core/format.dart';
import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/features/inventory/domain/stock_item.dart';
import 'package:wholeflow_app/features/purchases/domain/purchase.dart';
import 'package:wholeflow_app/features/suppliers/domain/supplier.dart';

StockItem item(String name, {double qty = 0, double? min, double reorder = 0, String? group, String? value}) => StockItem(
  id: name,
  name: name,
  closingQty: qty,
  minQty: min,
  reorderLevel: reorder,
  group: group,
  closingValue: value == null ? null : Money.parse(value),
);

Supplier supplier(String name, String payable, {String? phone}) =>
    Supplier(id: name, companyId: 'c', name: name, payable: Money.parse(payable), phone: phone);

void main() {
  group('minimum stock and the stock alert', () {
    test('the below-minimum filter matches the stock alert, out of stock included', () {
      final items = [item('a', qty: 0, min: 4), item('b', qty: 3, min: 8), item('c', qty: 20, min: 8), item('d', qty: 0)];
      final shown = filterStock(items, const StockFilter(belowMinimum: true)).map((i) => i.id).toSet();
      expect(shown, stockAlerts(items).map((i) => i.id).toSet());
      expect(shown, {'a', 'b'});
      expect(const StockFilter(belowMinimum: true).isFiltered, isTrue);
    });

    test('the owner\'s minimum wins over Tally\'s reorder level', () {
      expect(item('a', qty: 8, min: 10, reorder: 5).effectiveMin, 10);
      expect(item('a', qty: 8, reorder: 5).effectiveMin, 5, reason: 'no minimum set: Tally reorder level');
      expect(item('a', qty: 8).hasMinimum, isFalse);
    });

    test('alert at or below the minimum, including out of stock and negative', () {
      expect(item('a', qty: 10, min: 10).atOrBelowMinimum, isTrue, reason: 'at the minimum');
      expect(item('a', qty: 10.5, min: 10).atOrBelowMinimum, isFalse);
      expect(item('a', qty: 0, min: 10).atOrBelowMinimum, isTrue);
      expect(item('a', qty: -2, min: 10).atOrBelowMinimum, isTrue);
      expect(item('a', qty: 0).atOrBelowMinimum, isFalse, reason: 'no minimum: no alert');
    });

    test('status follows quantity and minimum', () {
      expect(item('a', qty: 3, min: 5).status, StockStatus.low);
      expect(item('a', qty: 30, min: 5).status, StockStatus.inStock);
      expect(item('a', qty: 0, min: 5).status, StockStatus.zero);
      expect(item('a', qty: -1).status, StockStatus.negative);
      expect(item('a', qty: 3).status, StockStatus.inStock, reason: 'no minimum: not low');
    });

    test('withMinimum sets and clears; 0 counts as cleared', () {
      final i = item('a', qty: 3, reorder: 2);
      expect(i.withMinimum(5).minQty, 5);
      expect(i.withMinimum(5).status, StockStatus.low);
      expect(i.withMinimum(null).minQty, isNull);
      expect(i.withMinimum(0).minQty, isNull);
      expect(i.withMinimum(0).effectiveMin, 2);
    });

    test('alerts list: furthest below the minimum first', () {
      final alerts = stockAlerts([
        item('half', qty: 5, min: 10),
        item('ok', qty: 50, min: 10),
        item('empty', qty: 0, min: 4),
        item('slightly', qty: 9, min: 10),
        item('none', qty: 0),
      ]);
      expect(alerts.map((i) => i.name), ['empty', 'half', 'slightly']);
      expect(alerts.first.shortfall, 4);
    });
  });

  group('StockItem.fromJson', () {
    test('owner row from v_stock_items', () {
      final i = StockItem.fromJson({
        'stock_item_id': 'i1',
        'name': 'TYRE 145/80 R12',
        'aliases': ['P-100', ''],
        'stock_group': 'Tyres',
        'unit': 'Nos',
        'closing_qty': '12.500',
        'closing_rate': '1008.94',
        'closing_value': 6053.63,
        'reorder_level': 10,
        'stock_status': 'low',
        'synced_at': '2026-09-28T10:00:00Z',
        'last_purchase_date': '2026-09-01',
        'last_purchase_rate': '990.00',
        'last_supplier': 'MRF LTD',
      });
      expect(i.id, 'i1');
      expect(i.aliases, ['P-100']);
      expect(i.closingQty, 12.5);
      expect(i.closingRate, const Money(100894));
      expect(i.closingValue, const Money(605363));
      expect(i.status, StockStatus.inStock, reason: '12.5 is above the reorder level of 10');
      expect(i.lastPurchaseDate, DateTime(2026, 9));
      expect(i.lastPurchaseRate, const Money(99000));
    });

    test('staff row from stock_items has no costs', () {
      final i = StockItem.fromJson({'id': 'i2', 'name': 'TUBE', 'closing_qty': -2, 'stock_status': 'negative'});
      expect(i.id, 'i2');
      expect(i.closingRate, isNull);
      expect(i.closingValue, isNull);
      expect(i.lastPurchaseRate, isNull);
      expect(i.status, StockStatus.negative);
    });

    test('unknown status falls back to zero', () {
      expect(StockStatus.parse('weird'), StockStatus.zero);
    });
  });

  group('filterStock', () {
    final items = [
      item('Bolt', qty: 5, group: 'Hardware', value: '50'),
      item('axle', qty: 1, min: 5, group: 'Parts', value: '900'),
      item('Cable'),
    ];

    test('status, group and search', () {
      expect(filterStock(items, const StockFilter(status: StockStatus.low)).map((i) => i.name), ['axle']);
      expect(filterStock(items, const StockFilter(group: '')).map((i) => i.name), ['Cable']);
      expect(filterStock(items, const StockFilter(query: 'HARD')).map((i) => i.name), ['Bolt']);
    });

    test('sorts', () {
      expect(filterStock(items, const StockFilter()).map((i) => i.name), ['axle', 'Bolt', 'Cable']);
      expect(filterStock(items, const StockFilter(sort: StockSort.qtyDesc)).map((i) => i.name), ['Bolt', 'axle', 'Cable']);
      expect(filterStock(items, const StockFilter(sort: StockSort.valueDesc)).map((i) => i.name), ['axle', 'Bolt', 'Cable']);
    });

    test('copyWith can clear status and group', () {
      const f = StockFilter(status: StockStatus.low, group: 'Parts');
      final cleared = f.copyWith(status: () => null, group: () => null);
      expect(cleared.status, isNull);
      expect(cleared.group, isNull);
      expect(f.copyWith(query: 'x').status, StockStatus.low);
    });

    test('summary', () {
      final s = StockSummary.of(items);
      expect(s.items, 3);
      expect(s.value, const Money(95000));
      expect(s.byStatus[StockStatus.low], 1);
      expect(s.byStatus[StockStatus.zero], 1);
      expect(stockGroups(items), ['', 'Hardware', 'Parts']);
    });
  });

  group('purchases', () {
    test('detail parses lines in order and signed ledger entries', () {
      final d = PurchaseDetail.fromJson({
        'id': 'p1',
        'purchase_date': '2026-09-15',
        'supplier_id': 's1',
        'supplier_name': 'MRF LTD',
        'voucher_number': '42',
        'taxable_amount': '1000.00',
        'tax_and_other_amount': '179.60',
        'total_amount': '1179.60',
        'line_count': 2,
        'total_qty': '3',
        'ledger_entries': [
          {'ledger': 'IGST', 'amount': 180, 'type': 'DR'},
          {'ledger': 'Round off', 'amount': 0.4, 'type': 'CR'},
        ],
        'purchase_lines': [
          {'line_no': 2, 'item_name': 'B', 'qty': 1, 'rate': '400', 'amount': '400'},
          {'line_no': 1, 'item_name': 'A', 'qty': '2', 'rate': '300', 'amount': '600'},
        ],
      });
      expect(d.lines.map((l) => l.itemName), ['A', 'B']);
      expect(d.lines.first.qty, 2);
      expect(d.ledgerEntries.map((e) => e.amount), [const Money(18000), const Money(-40)]);
      final sum = d.summary.taxable + d.ledgerEntries.fold(Money.zero, (s, e) => s + e.amount);
      expect(sum, d.summary.total);
    });

    test('item purchase sums the item lines of a bill', () {
      final p = ItemPurchase.fromJson({
        'id': 'p1',
        'purchase_date': '2026-09-15',
        'supplier_name': 'MRF',
        'purchase_lines': [
          {'qty': 2, 'unit': 'Nos', 'rate': '100', 'amount': '200'},
          {'qty': '1', 'unit': 'Nos', 'rate': '100', 'amount': '100'},
        ],
      });
      expect(p.qty, 3);
      expect(p.amount, const Money(30000));
      expect(p.rate, const Money(10000));
    });

    test('month totals add up suppliers, newest first', () {
      final months = monthTotalsOf([
        {'month': '2026-08-01', 'bills': 2, 'total_amount': '100.50'},
        {'month': '2026-09-01', 'bills': 1, 'total_amount': 10},
        {'month': '2026-08-01', 'bills': 3, 'total_amount': '0.50'},
      ]);
      expect(months.map((m) => m.month), [DateTime(2026, 9), DateTime(2026, 8)]);
      expect(months.last.bills, 5);
      expect(months.last.total, const Money(10100));
    });
  });

  group('suppliers', () {
    test('opening balance uses the payable sign (Cr = owed)', () {
      final s = Supplier.fromJson({
        'id': 's1',
        'company_id': 'c',
        'name': 'MRF',
        'payable': '-250.00',
        'opening_balance_amount': '1000',
        'opening_balance_type': 'CR',
      });
      expect(s.payable, const Money(-25000));
      expect(s.openingPayable, const Money(100000));
    });

    test('filter, sort and total owed', () {
      final all = [supplier('b', '100'), supplier('A', '-50', phone: '98470 12345'), supplier('c', '0'), supplier('d', '300')];
      expect(filterSuppliers(all).map((s) => s.name), ['d', 'b', 'c', 'A']);
      expect(filterSuppliers(all, sort: SupplierSort.name).map((s) => s.name), ['A', 'b', 'c', 'd']);
      expect(filterSuppliers(all, filter: PayableFilter.advance).map((s) => s.name), ['A']);
      expect(filterSuppliers(all, query: '98470').map((s) => s.name), ['A']);
      expect(totalOwed(all), const Money(40000));
    });
  });

  test('formatQty', () {
    expect(formatQty(1250, 'Nos'), '1,250 Nos');
    expect(formatQty(125000.5), '1,25,000.5');
    expect(formatQty(-2, ' '), '-2');
    expect(parseQty('12.500'), 12.5);
    expect(parseQty(null), 0);
  });
}
