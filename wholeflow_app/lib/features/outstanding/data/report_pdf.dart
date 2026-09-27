import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../domain/outstanding_report.dart';

/// A4 PDF of the outstanding report. Uses the built-in Helvetica, which has no
/// rupee sign, so amounts are written as "Rs.".
Future<Uint8List> outstandingReportPdf(OutstandingReport r) {
  final doc = pw.Document(title: 'Outstanding - ${r.companyName}', creator: 'WholeFlow');
  final bold = const pw.TextStyle(fontWeight: pw.FontWeight.bold);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Outstanding - ${r.companyName}', style: const pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text('As of ${formatDateTime(r.generatedAt)} · ${r.shopCount} shops · Total ${formatInrPlain(r.total)}'),
          pw.SizedBox(height: 12),
        ],
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 9)),
      ),
      build: (context) => [
        for (final g in r.groups) ...[
          pw.Container(
            color: PdfColors.grey200,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: pw.Row(
              children: [
                pw.Expanded(child: pw.Text(g.area, style: bold)),
                pw.Text(formatInrPlain(g.subtotal), style: bold),
              ],
            ),
          ),
          for (final s in g.shops)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: pw.Row(
                children: [
                  pw.Expanded(child: pw.Text(s.name)),
                  if (s.phone != null) pw.SizedBox(width: 90, child: pw.Text(s.phone!, style: const pw.TextStyle(fontSize: 9))),
                  pw.SizedBox(width: 100, child: pw.Text(formatInrPlain(s.receivable), textAlign: pw.TextAlign.right)),
                ],
              ),
            ),
          pw.SizedBox(height: 8),
        ],
        pw.Divider(),
        pw.Row(
          children: [
            pw.Expanded(child: pw.Text('Grand total', style: bold)),
            pw.Text(formatInrPlain(r.total), style: bold),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}
