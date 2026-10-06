import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../domain/customer_statement.dart';

/// A4 PDF of a shop's statement of account, for the customer. Uses the
/// built-in Helvetica, which has no rupee sign, so amounts are written as "Rs.".
Future<Uint8List> customerStatementPdf(CustomerStatement c) {
  final p = c.period;
  // Helvetica has no en dash.
  final period = c.periodLabel.replaceAll(' – ', ' to ');
  final doc = pw.Document(title: 'Statement of account - ${c.shop.name}', creator: 'WholeFlow');
  const bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  const small = pw.TextStyle(fontSize: 9);
  const smallBold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
  const grey = PdfColors.grey700;
  String plain(Money m) => m.isZero ? '' : formatInrPlain(m);
  String balance(Money m) => m.side == null ? formatInrPlain(Money.zero) : '${formatInrPlain(m.abs())} ${m.side!.label}';

  pw.Widget row(List<String> cells, {pw.TextStyle style = small, PdfColor? color}) => pw.Container(
    color: color,
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: 64, child: pw.Text(cells[0], style: style)),
        pw.Expanded(child: pw.Text(cells[1], style: style)),
        for (final amount in cells.skip(2))
          pw.SizedBox(
            width: 86,
            child: pw.Text(amount, style: style, textAlign: pw.TextAlign.right),
          ),
      ],
    ),
  );

  final address = c.shop.fullAddress;
  final gstin = c.shop.gstin?.trim() ?? '';
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text('${c.shop.name} - $period', style: const pw.TextStyle(fontSize: 9, color: grey)),
            ),
      footer: (context) => pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text('Generated ${formatDateTime(c.generatedAt)}', style: const pw.TextStyle(fontSize: 8, color: grey)),
          ),
          pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: small),
        ],
      ),
      build: (context) => [
        pw.Text(c.companyName, style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text('Statement of account', style: const pw.TextStyle(fontSize: 12, color: grey)),
        pw.SizedBox(height: 16),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('To', style: const pw.TextStyle(fontSize: 9, color: grey)),
                  pw.Text(c.shop.name, style: bold),
                  if (address != null) pw.Text(address, style: small),
                  if (gstin.isNotEmpty) pw.Text('GSTIN: $gstin', style: small),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Period', style: const pw.TextStyle(fontSize: 9, color: grey)),
                pw.Text(period, style: bold),
                pw.SizedBox(height: 6),
                pw.Text(balanceCaption(p.closing), style: const pw.TextStyle(fontSize: 9, color: grey)),
                pw.Text(balance(p.closing), style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        row(['Date', 'Voucher', 'Debit', 'Credit', 'Balance'], style: smallBold, color: PdfColors.grey200),
        row(['', 'Opening balance', '', '', balance(p.opening)], style: smallBold),
        for (final l in p.lines)
          row([
            formatDate(l.transaction.transactionDate),
            voucherLabel(l.transaction).isEmpty ? l.transaction.category.label : voucherLabel(l.transaction),
            plain(l.transaction.debit),
            plain(l.transaction.credit),
            balance(l.balanceAfter),
          ]),
        if (p.lines.isEmpty) row(['', 'No transactions in this period', '', '', '']),
        pw.Divider(height: 8, color: PdfColors.grey400),
        row(['', 'Total', plain(p.totalDebit), plain(p.totalCredit), ''], style: smallBold),
        row(['', 'Closing balance', '', '', balance(p.closing)], style: smallBold, color: PdfColors.grey200),
        pw.SizedBox(height: 16),
        pw.Text(
          'Dr = amount due to ${c.companyName}. Cr = advance or credit with ${c.companyName}. '
          'Please contact us if anything here does not match your records.',
          style: const pw.TextStyle(fontSize: 8, color: grey),
        ),
      ],
    ),
  );
  return doc.save();
}
