import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wholeflow_app/core/providers.dart';
import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/core/phone.dart';
import 'package:wholeflow_app/features/dashboard/domain/dashboard_models.dart';
import 'package:wholeflow_app/features/outstanding/domain/outstanding_report.dart';
import 'package:wholeflow_app/features/outstanding/domain/overdue_report.dart';
import 'package:wholeflow_app/features/shop_detail/domain/statement.dart';
import 'package:wholeflow_app/features/shops/domain/shop.dart';
import 'package:wholeflow_app/features/sites/domain/site.dart';
import 'package:wholeflow_app/features/staff/domain/staff.dart';

import '../widget/helpers.dart';

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

    // Balances are worked out on the server (internal/appapi/statement_test.go);
    // here: reading its answer and the on-screen filters.
    test('reads the server statement, newest first', () {
      final s = Statement.fromJson({
        'ledger_opening': '100.00',
        'tally_balance': '550.00',
        'computed_balance': '500.00',
        'reconciled': false,
        'lines': [
          {
            'id': 's2',
            'transaction_date': '2026-04-20',
            'category': 'sales',
            'debit': '200.00',
            'credit': '0.00',
            'amount': '200.00',
            'balance_after': '500.00',
          },
          {
            'id': 'r1',
            'transaction_date': '2026-04-10',
            'category': 'receipts',
            'debit': '0.00',
            'credit': '300.00',
            'amount': '-300.00',
            'balance_after': '300.00',
          },
        ],
      });
      expect(s.newestFirst.map((l) => l.transaction.id), ['s2', 'r1']);
      expect(s.newestFirst.first.balanceAfter, const Money(50000));
      expect(s.newestFirst.last.transaction.category, TxnCategory.receipts);
      expect(s.reconciled, isFalse);
      expect(s.difference, const Money(5000));
    });

    test('filters keep full-ledger balances', () async {
      final s = await FakeTransactionRepository(txns).statement('x');
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
    // Grouping and order are the server's (internal/appapi/shops_test.go).
    test('reads the server report and narrows it for search', () {
      final r = OutstandingReport.fromJson({
        'company_name': 'JMJ',
        'generated_at': '2026-09-28T06:00:00Z',
        'total': '5.20',
        'groups': [
          {
            'site_id': 'p',
            'site_name': 'Pala',
            'subtotal': '4.00',
            'shops': [
              {'shop_id': '2', 'name': 'B', 'receivable': '3.00', 'site_id': 'p', 'site_name': 'Pala'},
              {'shop_id': '1', 'name': 'A', 'area': 'Kply', 'receivable': '1.00', 'site_id': 'p', 'site_name': 'Pala'},
            ],
          },
          {
            'site_id': null,
            'site_name': null,
            'subtotal': '1.20',
            'shops': [
              {'shop_id': '3', 'name': 'C', 'receivable': '1.20'},
            ],
          },
        ],
      });
      expect(r.groups.map((g) => g.site), ['Pala', 'No site']);
      expect(r.groups.last.siteId, isNull);
      expect(r.groups.first.shops.map((s) => s.id), ['2', '1']);
      expect(r.total, const Money(520));
      expect(r.shopCount, 3);
      expect(outstandingReportText(r), contains('Pala — ₹4.00'));
      final a = r.narrowed((s) => s.name == 'A');
      expect(a.groups.single.shops.single.id, '1');
      expect(a.groups.single.subtotal, const Money(100));
      expect(a.total, const Money(100));
    });
  });

  group('overdue report', () {
    Map<String, dynamic> row(String id, String? site, num overdue, int days, {bool bills = true}) => {
      'shop_id': id,
      'name': 'Shop $id',
      'area': null,
      'site_id': site == null ? null : 'id-$site',
      'site_name': site,
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

    OverdueReport report(List<Map<String, dynamic>> shops, {int days = 30}) => OverdueReport.fromJson({
      'company_name': 'JMJ',
      'credit_days': days,
      'generated_at': '2026-09-29T06:00:00Z',
      'total': '${shops.fold<num>(0, (t, s) => t + (s['overdue'] as num))}',
      'groups': [
        {
          'site_id': 'id-Pala',
          'site_name': 'Pala',
          'subtotal': '${shops.fold<num>(0, (t, s) => t + (s['overdue'] as num))}',
          'shops': shops,
        },
      ],
    });

    test('reads the server report and lists bills in the text', () {
      final r = report([row('2', 'Pala', 300, 40), row('1', 'Pala', 100, 5)]);
      expect(r.groups.single.site, 'Pala');
      expect(r.groups.first.shops.map((s) => s.id), ['2', '1']);
      expect(r.total, const Money(40000));
      expect(r.showsBills, isTrue);
      final text = overdueReportText(r);
      expect(text, contains('Past 30 days credit — JMJ'));
      expect(text, contains('Shop 2: ₹300.00 · 40 days past limit'));
      expect(text, contains('Sales · 2 (10 Aug 2026): ₹300.00 due · 40 days past limit'));
      final narrowed = r.narrowed((s) => s.id == '1');
      expect(narrowed.total, const Money(10000));
      expect(narrowed.groups.single.shops.single.id, '1');
    });

    test('text has no bills when they are hidden', () {
      final r = report([row('1', 'Pala', 100, 1, bills: false)], days: 1);
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
    const sites = {'s1': 'Rajakkad', 's2': 'Pala'};

    test('access summary', () {
      final text = accessSummary(
        'Ravi',
        const [
          CompanyGrant(companyId: 'a'),
          CompanyGrant(companyId: 'b', fullCompany: false, siteIds: {'s1', 's2'}, canViewTransactions: false),
        ],
        names,
        sites,
      );
      expect(text, 'Ravi will see: JMJ Marketing (full company), JK Tyres (Pala, Rajakkad; no transactions)');
      expect(accessSummary('Ravi', const [], names, sites), "Ravi won't see any company's data.");
    });

    test('grant request body', () {
      expect(const CompanyGrant(companyId: 'a', fullCompany: false, siteIds: {'z', 'a'}).toRequest(), {
        'company_id': 'a',
        'full_company': false,
        'site_ids': ['a', 'z'],
        'can_view_transactions': true,
      });
      // Full company never sends sites, and is never missing sites.
      const full = CompanyGrant(companyId: 'a', siteIds: {'z'});
      expect(full.toRequest()['site_ids'], isEmpty);
      expect(full.needsSites, isFalse);
      expect(const CompanyGrant(companyId: 'a', fullCompany: false).needsSites, isTrue);
    });

    test('site report periods', () {
      final today = DateTime(2026, 2, 14);
      expect(ReportPeriod.thisMonth.range(today), (DateTime(2026, 2), DateTime(2026, 2, 14)));
      expect(ReportPeriod.lastMonth.range(today), (DateTime(2026, 1), DateTime(2026, 1, 31)));
      expect(ReportPeriod.last3Months.range(today), (DateTime(2025, 12), DateTime(2026, 2, 14)));
      expect(ReportPeriod.thisYear.range(today), (DateTime(2025, 4), DateTime(2026, 2, 14)));
      expect(ReportPeriod.thisYear.range(DateTime(2026, 4, 2)).$1, DateTime(2026, 4));
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
