import 'package:flutter_test/flutter_test.dart';
import 'package:wholeflow_app/core/money/money.dart';

void main() {
  group('Money.parse', () {
    test('handles PostgREST numbers and strings exactly', () {
      expect(Money.parse(3418745.27).paise, 341874527);
      expect(Money.parse('3418745.27').paise, 341874527);
      expect(Money.parse(100).paise, 10000);
      expect(Money.parse('0.1').paise + Money.parse('0.2').paise, 30);
      expect(Money.parse('-176499.68').paise, -17649968);
      expect(Money.parse('5').paise, 500);
      expect(Money.parse('.5').paise, 50);
      expect(Money.parse(null), Money.zero);
      expect(Money.parse('').paise, 0);
    });

    test('rejects garbage', () {
      expect(() => Money.parse('12a'), throwsFormatException);
      expect(() => Money.parse(true), throwsFormatException);
    });

    test('fromSide signs Tally amounts', () {
      expect(Money.fromSide('120.50', 'DR').paise, 12050);
      expect(Money.fromSide('120.50', 'CR').paise, -12050);
      expect(Money.fromSide(0, '').paise, 0);
    });
  });

  group('formatting', () {
    test('uses Indian lakh/crore grouping', () {
      expect(formatInr(const Money(341874527)), '₹34,18,745.27');
      expect(formatInr(const Money(359524495)), '₹35,95,244.95');
      expect(formatInr(const Money(1234567890)), '₹1,23,45,678.90');
      expect(formatInr(Money.zero), '₹0.00');
      expect(formatInr(const Money(-17649968)), '-₹1,76,499.68');
    });

    test('balance spells out the side', () {
      expect(formatBalance(const Money(120000)), '₹1,200.00 Dr');
      expect(formatBalance(const Money(-5000)), '₹50.00 Cr');
      expect(formatBalance(Money.zero), '₹0.00');
    });

    test('compact form for tiles', () {
      expect(formatInrCompact(const Money(341874527)), '₹34.2 L');
      expect(formatInrCompact(const Money(15000000000)), '₹15 crore');
      expect(formatInrCompact(const Money(1230000)), '₹12.3 K');
      expect(formatInrCompact(const Money(95000)), '₹950');
      expect(formatInrCompact(const Money(10000000)), '₹1 L');
      expect(formatInrCompact(const Money(-341874527)), '-₹34.2 L');
    });

    test('plain form avoids the rupee glyph', () {
      expect(formatInrPlain(const Money(341874527)), 'Rs. 34,18,745.27');
    });
  });

  test('side', () {
    expect(const Money(1).side, BalanceSide.dr);
    expect(const Money(-1).side, BalanceSide.cr);
    expect(Money.zero.side, isNull);
  });
}
