import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/features/shop_detail/data/statement_pdf.dart';
import 'package:wholeflow_app/features/shop_detail/domain/customer_statement.dart';
import 'package:wholeflow_app/features/shop_detail/domain/statement.dart';
import 'package:wholeflow_app/features/shop_detail/presentation/share_statement.dart';
import 'package:wholeflow_app/features/shops/domain/shop.dart';

import '../widget/helpers.dart';

ShopTransaction txn(String id, String date, int paise, {String? type, String? number, String? narration}) => ShopTransaction(
  id: id,
  transactionDate: DateTime.parse(date),
  category: paise > 0 ? TxnCategory.sales : TxnCategory.receipts,
  voucherType: type,
  voucherNumber: number,
  narration: narration,
  debit: Money(paise > 0 ? paise : 0),
  credit: Money(paise < 0 ? -paise : 0),
  amount: Money(paise),
);

void main() {
  // Opening 100; +500 (1 Mar), -300 (10 Apr), +200 (20 Apr), -50 (5 May).
  // Balances come from the server (internal/appapi/statement_test.go); the fake answers the same way.
  final statement = FakeTransactionRepository([
    txn('a', '2026-03-01', 50000, type: 'Sales', number: '11'),
    txn('b', '2026-04-10', -30000, type: 'Receipt', number: 'R4', narration: 'cash via Ravi, check later'),
    txn('c', '2026-04-20', 20000, type: 'Sales', number: '12'),
    txn('d', '2026-05-05', -5000, type: 'Credit Note', number: 'CN1'),
  ], const Money(10000));

  group('period choices', () {
    test('financial year runs 1 April – 31 March', () {
      final june = DateTime(2026, 6, 15, 10);
      expect(
        statementPeriodRange(StatementPeriod.thisYear, june),
        DateTimeRange(start: DateTime(2026, 4, 1), end: DateTime(2026, 6, 15)),
      );
      expect(
        statementPeriodRange(StatementPeriod.lastYear, june),
        DateTimeRange(start: DateTime(2025, 4, 1), end: DateTime(2026, 3, 31)),
      );
      final feb = DateTime(2027, 2, 10);
      expect(statementPeriodRange(StatementPeriod.thisYear, feb)!.start, DateTime(2026, 4, 1));
      expect(statementPeriodRange(StatementPeriod.all, feb), isNull);
    });

    test('last 3 months', () {
      final r = statementPeriodRange(StatementPeriod.threeMonths, DateTime(2026, 10, 6))!;
      expect(r.start, DateTime(2026, 7, 7));
      expect(r.end, DateTime(2026, 10, 6));
    });

    test('labels', () {
      expect(statementPeriodLabel(null, null), 'All transactions');
      expect(statementPeriodLabel(DateTime(2026, 4, 1), DateTime(2026, 10, 6)), '1 Apr 2026 – 6 Oct 2026');
    });
  });

  group('what the customer gets', () {
    const shop = ShopDetail(
      id: 's1',
      companyId: 'co-a',
      name: 'PRINCE TYRES -- RAJAKKAD',
      gstin: '32ABCDE1234F1Z5',
      address: 'Main Road, Rajakkad',
      siteName: 'Rajakkad route',
    );
    Future<CustomerStatement> customer({DateTime? from, DateTime? to}) async => CustomerStatement(
      companyName: 'Demo Traders',
      shop: shop,
      period: await statement.period('s1', from: from, to: to),
      generatedAt: DateTime(2026, 10, 6, 12),
    );

    test('text lists the vouchers and the balance due, without narrations or site', () async {
      final text = customerStatementText(await customer(from: DateTime(2026, 4, 1), to: DateTime(2026, 4, 30)));
      expect(text, contains('PRINCE TYRES -- RAJAKKAD'));
      expect(text, contains('From: Demo Traders'));
      expect(text, contains('Period: 1 Apr 2026 – 30 Apr 2026'));
      expect(text, contains('Opening balance: ₹600.00 Dr'));
      expect(text, contains('10 Apr 2026 · Receipt R4 · Credit ₹300.00'));
      expect(text, contains('20 Apr 2026 · Sales 12 · Debit ₹200.00'));
      expect(text, contains('Balance due as of 30 Apr 2026: ₹500.00 Dr'));
      expect(text, isNot(contains('Ravi')));
      expect(text, isNot(contains('Rajakkad route')));
    });

    test('long statements send totals only as text', () async {
      final many = FakeTransactionRepository([
        for (var i = 0; i < statementTextMaxLines + 1; i++) txn('t$i', '2026-04-01', i.isEven ? 100 : -100),
      ]);
      final text = customerStatementText(
        CustomerStatement(
          companyName: 'Demo Traders',
          shop: shop,
          period: await many.period('s1'),
          generatedAt: DateTime(2026, 10, 6),
        ),
      );
      expect(text, contains('41 entries (ask for the PDF for details)'));
      expect(text, isNot(contains('1 Apr 2026 ·')));
    });

    test('an advance reads as an advance', () async {
      final credit = FakeTransactionRepository([txn('x', '2026-04-01', -2000)]);
      final text = customerStatementText(
        CustomerStatement(
          companyName: 'Demo Traders',
          shop: shop,
          period: await credit.period('s1'),
          generatedAt: DateTime(2026, 10, 6),
        ),
      );
      expect(text, contains('Advance with us as of 6 Oct 2026: ₹20.00 Cr'));
    });

    test('PDF is made', () async {
      final bytes = await customerStatementPdf(await customer());
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    });

    test('file name', () async {
      expect((await customer(to: DateTime(2026, 4, 30))).fileStem, 'statement-prince-tyres-rajakkad-2026-04-30');
    });
  });
}
