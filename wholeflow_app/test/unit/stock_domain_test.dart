import 'package:flutter_test/flutter_test.dart';
import 'package:wholeflow_app/core/format.dart';
import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/features/inventory/domain/stock_item.dart';
import 'package:wholeflow_app/features/purchases/domain/purchase.dart';
import 'package:wholeflow_app/features/suppliers/domain/supplier.dart';

import '../stock_like_server.dart';

StockItem item(String name, {double qty = 0, double? min, double reorder = 0, String? group, String? value}) =>
    stockItem(id: name, qty: qty, min: min, reorder: reorder, group: group, value: value == null ? null : Money.parse(value));

Supplier supplier(String name, String payable, {String? phone}) =>
    Supplier(id: name, companyId: 'c', name: name, payable: Money.parse(payable), phone: phone);

void main() {
  // Status, minimum and alert rules are the server's (internal/appapi/stock_test.go).
  group('stock alert filter', () {
    test('the below-minimum filter shows the items the server flags, out of stock included', () {
      final items = [item('a', qty: 0, min: 4), item('b', qty: 3, min: 8), item('c', qty: 20, min: 8), item('d', qty: 0)];
      final shown = filterStock(items, const StockFilter(belowMinimum: true)).map((i) => i.id).toSet();
      expect(shown, {'a', 'b'});
      expect(const StockFilter(belowMinimum: true).isFiltered, isTrue);
    });

    test('reads the server list: alerts in its order, summary as sent', () {
      final list = StockList.fromJson({
        'items': [
          {
            'stock_item_id': 'a',
            'name': 'A',
            'closing_qty': 0,
            'min_qty': 4,
            'effective_min': 4,
            'status': 'zero',
            'at_or_below_minimum': true,
            'shortfall': 4,
          },
          {
            'stock_item_id': 'b',
            'name': 'B',
            'closing_qty': 9,
            'effective_min': 10,
            'status': 'low',
            'at_or_below_minimum': true,
            'shortfall': 1,
          },
          {'stock_item_id': 'c', 'name': 'C', 'closing_qty': 20, 'status': 'in_stock'},
        ],
        'summary': {
          'items': 3,
          'value': '950.00',
          'by_status': {'zero': 1, 'low': 1, 'in_stock': 1},
          'synced_at': '2026-10-08T05:00:00Z',
        },
        'alerts': ['b', 'a'],
      });
      expect(list.alerts.map((i) => i.id), ['b', 'a']);
      expect(list.items.first.minQty, 4);
      expect(list.items[1].minQty, isNull, reason: 'Tally reorder level, no owner minimum');
      expect(list.items[1].hasMinimum, isTrue);
      expect(list.summary.value, const Money(95000));
      expect(list.summary.byStatus[StockStatus.negative], 0);
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
        'status': 'in_stock',
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
      expect(i.status, StockStatus.inStock, reason: 'as the server sends it');
      expect(i.lastPurchaseDate, DateTime(2026, 9));
      expect(i.lastPurchaseRate, const Money(99000));
    });

    test('staff row from stock_items has no costs', () {
      final i = StockItem.fromJson({'id': 'i2', 'name': 'TUBE', 'closing_qty': -2, 'status': 'negative'});
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

    test('groups', () {
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

    test('month totals as the server sends them', () {
      final m = MonthPurchases.fromJson({'month': '2026-08-01', 'bills': 5, 'total_amount': 101});
      expect(m.month, DateTime(2026, 8));
      expect(m.bills, 5);
      expect(m.total, const Money(10100));
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
