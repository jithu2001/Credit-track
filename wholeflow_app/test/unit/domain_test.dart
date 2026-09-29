import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/core/phone.dart';
import 'package:wholeflow_app/features/dashboard/domain/dashboard_models.dart';
import 'package:wholeflow_app/features/outstanding/domain/outstanding_report.dart';
import 'package:wholeflow_app/features/outstanding/domain/overdue_report.dart';
import 'package:wholeflow_app/features/shop_detail/domain/statement.dart';
import 'package:wholeflow_app/features/shops/data/shop_repository.dart';
import 'package:wholeflow_app/features/shops/domain/shop.dart';
import 'package:wholeflow_app/features/staff/domain/staff.dart';

ShopTransaction txn(String id, String date, int amountPaise, {TxnCategory c = TxnCategory.sales}) => ShopTransaction(
  id: id,
  transactionDate: DateTime.parse(date),
  category: c,
  debit: Money(amountPaise > 0 ? amountPaise : 0),
  credit: Money(amountPaise < 0 ? -amountPaise : 0),
  amount: Money(amountPaise),
);

void main() {
  group('statement', () {
    final txns = [
      txn('r1', '2026-04-10', -30000, c: TxnCategory.receipts),
      txn('s1', '2026-04-01', 50000),
      txn('s2', '2026-04-20', 20000),
    ];

    test('running balance from the opening balance, newest first', () {
      final s = buildStatement(opening: const Money(10000), closing: const Money(50000), transactions: txns);
      expect(s.newestFirst.map((l) => l.transaction.id), ['s2', 'r1', 's1']);
      expect(s.newestFirst.map((l) => l.balanceAfter.paise), [50000, 30000, 60000]);
      expect(s.reconciled, isTrue);
    });

    test('flags a mismatch with the synced balance', () {
      final s = buildStatement(opening: const Money(10000), closing: const Money(55000), transactions: txns);
      expect(s.reconciled, isFalse);
      expect(s.difference, const Money(5000));
    });

    test('filters keep full-ledger balances', () {
      final s = buildStatement(opening: Money.zero, closing: const Money(40000), transactions: txns);
      final receipts = s.filtered(categories: {TxnCategory.receipts});
      expect(receipts.single.balanceAfter, const Money(20000));
      final april = s.filtered(from: DateTime(2026, 4, 5), to: DateTime(2026, 4, 15));
      expect(april.map((l) => l.transaction.id), ['r1']);
    });

    test('address does not repeat state and PIN already in the lines', () {
      const shop = ShopDetail(
        id: 'x',
        companyId: 'c',
        name: 'n',
        addressLines: ['AGP XV/930, N H Road', 'Idukki, Kerala, 685561'],
        state: 'Kerala',
        pincode: '685561',
      );
      expect(shop.fullAddress, 'AGP XV/930, N H Road\nIdukki, Kerala, 685561');
      const bare = ShopDetail(
        id: 'x',
        companyId: 'c',
        name: 'n',
        addressLines: ['Main Road'],
        state: 'Kerala',
        pincode: '685561',
      );
      expect(bare.fullAddress, 'Main Road\nKerala 685561');
    });

    test('Dr/Cr opening balance sign', () {
      const dr = ShopDetail(id: 'x', companyId: 'c', name: 'n', openingBalanceAmount: Money(100), openingBalanceType: 'DR');
      const cr = ShopDetail(id: 'x', companyId: 'c', name: 'n', openingBalanceAmount: Money(100), openingBalanceType: 'CR');
      expect(dr.openingBalance, const Money(100));
      expect(cr.openingBalance, const Money(-100));
    });
  });

  group('outstanding report', () {
    test('groups by area A–Z with No area last, highest dues first', () {
      final r = buildOutstandingReport(
        companyName: 'JMJ',
        generatedAt: DateTime(2026, 9, 28),
        shops: const [
          ShopSummary(id: '1', name: 'A', area: 'Pala', receivable: Money(100)),
          ShopSummary(id: '2', name: 'B', area: 'Pala', receivable: Money(300)),
          ShopSummary(id: '3', name: 'C', receivable: Money(50)),
          ShopSummary(id: '4', name: 'D', area: 'Kply', receivable: Money(70)),
          ShopSummary(id: '5', name: 'E', area: 'Kply', receivable: Money(-70)),
        ],
      );
      expect(r.groups.map((g) => g.area), ['Kply', 'Pala', 'No area']);
      expect(r.groups[1].shops.map((s) => s.id), ['2', '1']);
      expect(r.groups[1].subtotal, const Money(400));
      expect(r.total, const Money(520));
      expect(r.shopCount, 4);
      expect(outstandingReportText(r), contains('Pala — ₹4.00'));
    });
  });

  group('overdue report', () {
    Map<String, dynamic> row(String id, String? area, num overdue, int days, {bool bills = true}) => {
      'shop_id': id,
      'name': 'Shop $id',
      'area': area,
      'phone': null,
      'receivable': '1000.50',
      'overdue': overdue,
      'max_days_overdue': days,
      'overdue_bills': 1,
      'bills_visible': bills,
      'bills': bills
          ? [
              {'date': '2026-08-10', 'voucher': 'Sales · $id', 'amount': 500, 'remaining': overdue, 'days_overdue': days},
            ]
          : null,
    };

    test('parses the function row, with and without bills', () {
      final s = OverdueShop.fromJson(row('1', 'Pala', 300, 20));
      expect(s.receivable, const Money(100050));
      expect(s.overdue, const Money(30000));
      expect(s.maxDaysOverdue, 20);
      expect(s.bills!.single.voucher, 'Sales · 1');
      expect(s.bills!.single.date, DateTime(2026, 8, 10));
      expect(OverdueShop.fromJson(row('2', 'Pala', 300, 20, bills: false)).bills, isNull);
    });

    test('groups by area, most overdue first, and lists bills in the text', () {
      final r = buildOverdueReport(
        companyName: 'JMJ',
        creditDays: 30,
        generatedAt: DateTime(2026, 9, 29),
        shops: [
          OverdueShop.fromJson(row('1', 'Pala', 100, 5)),
          OverdueShop.fromJson(row('2', 'Pala', 300, 40)),
          OverdueShop.fromJson(row('3', null, 50, 10)),
          OverdueShop.fromJson(row('4', 'Kply', 0, 0)),
        ],
      );
      expect(r.groups.map((g) => g.area), ['Pala', 'No area']);
      expect(r.groups.first.shops.map((s) => s.id), ['2', '1']);
      expect(r.total, const Money(45000));
      expect(r.showsBills, isTrue);
      final text = overdueReportText(r);
      expect(text, contains('Past 30 days credit — JMJ'));
      expect(text, contains('Shop 2: ₹300.00 · 40 days past limit'));
      expect(text, contains('Sales · 2 (10 Aug 2026): ₹300.00 due · 40 days past limit'));
    });

    test('text has no bills when they are hidden', () {
      final r = buildOverdueReport(
        companyName: 'JMJ',
        creditDays: 1,
        generatedAt: DateTime(2026, 9, 29),
        shops: [OverdueShop.fromJson(row('1', 'Pala', 100, 1, bills: false))],
      );
      expect(r.showsBills, isFalse);
      expect(overdueReportText(r), contains('Past 1 day credit'));
      expect(overdueReportText(r), isNot(contains('Sales')));
    });
  });

  group('freshness', () {
    final now = DateTime(2026, 9, 28, 12);

    test('fresh within an hour', () {
      final f = evaluateFreshness(
        state: SyncState(lastSuccessfulSyncAt: now.subtract(const Duration(minutes: 4))),
        companySyncStatus: 'SYNCED',
        now: now,
      );
      expect(f.level, FreshnessLevel.fresh);
      expect(f.headline, 'Updated 4 min ago');
    });

    test('stale after an hour', () {
      final f = evaluateFreshness(
        state: SyncState(lastSuccessfulSyncAt: now.subtract(const Duration(hours: 3))),
        companySyncStatus: 'SYNCED',
        now: now,
      );
      expect(f.level, FreshnessLevel.warning);
      expect(f.detail, 'Updated 3 h ago');
    });

    test('Tally offline wording', () {
      final f = evaluateFreshness(
        state: SyncState(lastSuccessfulSyncAt: now.subtract(const Duration(minutes: 2)), status: 'error'),
        companySyncStatus: 'TALLY_OFFLINE',
        now: now,
      );
      expect(f.level, FreshnessLevel.warning);
      expect(f.headline, 'Tally PC is offline — figures may be out of date');
    });

    test('never synced', () {
      final f = evaluateFreshness(state: null, companySyncStatus: 'PENDING', now: now);
      expect(f.level, FreshnessLevel.warning);
    });
  });

  group('staff', () {
    const names = {'a': 'JMJ Marketing', 'b': 'JK Tyres'};

    test('access summary', () {
      final text = accessSummary('Ravi', const [
        CompanyGrant(companyId: 'a'),
        CompanyGrant(companyId: 'b', areas: {'Rajakkad', 'Pala'}, canViewTransactions: false),
      ], names);
      expect(text, 'Ravi will see: JMJ Marketing (all areas), JK Tyres (Pala, Rajakkad; no transactions)');
      expect(accessSummary('Ravi', const [], names), "Ravi won't see any company's data.");
    });

    test('grant request body', () {
      expect(const CompanyGrant(companyId: 'a', areas: {'Z', 'A'}).toRequest(), {
        'company_id': 'a',
        'areas': ['A', 'Z'],
        'can_view_transactions': true,
      });
    });

    test('generated passwords are long enough and mixed', () {
      for (var i = 0; i < 50; i++) {
        final p = generatePassword(random: Random(i));
        expect(p.length, 10);
        expect(p, matches(RegExp(r'\d')));
        expect(p, isNot(matches(RegExp('[0O1lI]'))));
      }
    });
  });

  test('phone links', () {
    expect(toInternationalIndian('98470 12345'), '919847012345');
    expect(toInternationalIndian('+91 98470-12345'), '919847012345');
    expect(toInternationalIndian('09847012345'), '919847012345');
    expect(toInternationalIndian('4862'), isNull);
    expect(whatsAppUri('9847012345').toString(), 'https://wa.me/919847012345');
    expect(telUri('9847012345').toString(), 'tel:+919847012345');
  });

  test('search is made safe for PostgREST or-filters', () {
    expect(sanitizeSearch(' prince, (tyres)* '), 'prince tyres');
    expect(sanitizeSearch('98%47'), '98 47');
  });
}
