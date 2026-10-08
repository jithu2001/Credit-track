import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/phone.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/share.dart';
import '../../../core/widgets/states.dart';
import '../../company/presentation/company_providers.dart';
import '../../shops/domain/shop.dart';
import '../data/statement_pdf.dart';
import '../domain/customer_statement.dart';
import '../domain/statement.dart';
import 'shop_detail_providers.dart';

/// The periods offered when sharing a statement.
enum StatementPeriod {
  shown('Dates shown'),
  thisYear('This financial year'),
  lastYear('Last financial year'),
  threeMonths('Last 3 months'),
  all('All transactions'),
  custom('Choose dates…');

  const StatementPeriod(this.label);
  final String label;
}

/// The dates of [period] on [today] (Indian financial year: 1 April – 31 March).
DateTimeRange? statementPeriodRange(StatementPeriod period, DateTime today, {DateTimeRange? shown}) {
  final day = DateTime(today.year, today.month, today.day);
  final fyStart = DateTime(day.month >= 4 ? day.year : day.year - 1, 4, 1);
  return switch (period) {
    StatementPeriod.shown || StatementPeriod.custom => shown,
    StatementPeriod.thisYear => DateTimeRange(start: fyStart, end: day),
    StatementPeriod.lastYear => DateTimeRange(start: DateTime(fyStart.year - 1, 4, 1), end: DateTime(fyStart.year, 3, 31)),
    StatementPeriod.threeMonths => DateTimeRange(start: DateTime(day.year, day.month - 3, day.day + 1), end: day),
    StatementPeriod.all => null,
  };
}

/// Opens "Share statement" for [shop]: pick the period, then send it as a PDF
/// or text through the share sheet, or as text straight to the shop's WhatsApp.
Future<void> showShareStatement(BuildContext context, ShopDetail shop) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => ShareStatementSheet(shop: shop),
);

class ShareStatementSheet extends ConsumerStatefulWidget {
  const ShareStatementSheet({super.key, required this.shop});

  final ShopDetail shop;

  @override
  ConsumerState<ShareStatementSheet> createState() => _ShareStatementSheetState();
}

class _ShareStatementSheetState extends ConsumerState<ShareStatementSheet> {
  late StatementPeriod _period;
  DateTimeRange? _custom;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _custom = ref.read(statementRangeProvider(widget.shop.id));
    _period = _custom != null ? StatementPeriod.shown : StatementPeriod.thisYear;
  }

  DateTimeRange? get _range => statementPeriodRange(_period, DateTime.now(), shown: _custom);

  Future<void> _choose(StatementPeriod p) async {
    if (p != StatementPeriod.custom) return setState(() => _period = p);
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _custom ?? statementPeriodRange(StatementPeriod.thisYear, now),
      helpText: 'Statement period',
    );
    if (picked != null && mounted) {
      setState(() {
        _custom = picked;
        _period = StatementPeriod.custom;
      });
    }
  }

  CustomerStatement _build(PeriodStatement period) {
    final companies = ref.read(companiesProvider).value ?? const [];
    final company = companies.where((c) => c.id == widget.shop.companyId).firstOrNull;
    return CustomerStatement(
      companyName: company?.companyName ?? '',
      shop: widget.shop,
      period: period,
      generatedAt: DateTime.now(),
    );
  }

  Future<void> _send(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, AppFailure.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the shop's WhatsApp chat with the text typed in; the user still taps Send.
  Future<void> _whatsApp(Uri chat, String text) async {
    final ok = await launchUrl(chat.replace(queryParameters: {'text': text}), mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      showMessage(context, "Couldn't open WhatsApp.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    final statement = ref.watch(statementPeriodProvider((shopId: widget.shop.id, from: range?.start, to: range?.end)));
    final periods = [
      if (_custom != null && _period != StatementPeriod.custom) StatementPeriod.shown,
      StatementPeriod.thisYear,
      StatementPeriod.lastYear,
      StatementPeriod.threeMonths,
      StatementPeriod.all,
      StatementPeriod.custom,
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Share statement', style: context.text.titleLarge),
            Text(widget.shop.name, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
            const SizedBox(height: Insets.l),
            Text('Period', style: context.text.labelLarge),
            const SizedBox(height: Insets.s),
            Wrap(
              spacing: Insets.s,
              runSpacing: Insets.s,
              children: [
                for (final p in periods)
                  ChoiceChip(
                    label: Text(
                      p == StatementPeriod.custom && _period == StatementPeriod.custom && _custom != null
                          ? statementPeriodLabel(_custom!.start, _custom!.end)
                          : p.label,
                    ),
                    selected: _period == p,
                    onSelected: _busy ? null : (_) => _choose(p),
                  ),
              ],
            ),
            const SizedBox(height: Insets.l),
            switch (statement) {
              AsyncValue(:final value?) => _ready(context, value),
              AsyncValue(:final error?) => Text(AppFailure.from(error).message),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ],
        ),
      ),
    );
  }

  Widget _ready(BuildContext context, PeriodStatement s) {
    final c = _build(s);
    final p = c.period;
    final phones = [
      for (final phone in widget.shop.allPhones)
        if (whatsAppUri(phone) case final uri?) (phone, uri),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card.filled(
          key: const Key('statement-summary'),
          child: Padding(
            padding: const EdgeInsets.all(Insets.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.periodLabel, style: context.text.titleSmall),
                const SizedBox(height: Insets.xs),
                Text(
                  '${plural(p.lines.length, 'entry', 'entries')} · Opening ${formatBalance(p.opening)}',
                  style: context.text.bodySmall,
                ),
                Text(
                  '${balanceCaption(p.closing)} ${formatBalance(p.closing)}',
                  style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        if (!s.reconciled) ...[
          const SizedBox(height: Insets.s),
          Card.filled(
            color: context.semantic.warningContainer,
            child: Padding(
              padding: const EdgeInsets.all(Insets.m),
              child: Text(
                "These transactions don't add up to the Tally balance (${formatBalance(s.tallyBalance)}). "
                'The statement shows balances worked out from the transactions. Sync again before sending if you can.',
                style: context.text.bodySmall?.copyWith(color: context.semantic.onWarningContainer),
              ),
            ),
          ),
        ],
        const SizedBox(height: Insets.s),
        Text(
          'Includes dates, vouchers, amounts and balances only. Narrations, site and location are left out.',
          style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        const SizedBox(height: Insets.l),
        FilledButton.icon(
          key: const Key('share-statement-pdf'),
          onPressed: _busy
              ? null
              : () => _send(() async => sharePdf(await customerStatementPdf(c), fileStem: c.fileStem, subject: c.subject)),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Share PDF'),
        ),
        const SizedBox(height: Insets.s),
        OutlinedButton.icon(
          key: const Key('share-statement-text'),
          onPressed: _busy ? null : () => _send(() => shareText(customerStatementText(c), subject: c.subject)),
          icon: const Icon(Icons.notes_rounded),
          label: const Text('Share as text'),
        ),
        for (final (phone, uri) in phones)
          TextButton.icon(
            onPressed: _busy ? null : () => _whatsApp(uri, customerStatementText(c)),
            icon: const Icon(Icons.chat_rounded),
            label: Text('Send text on WhatsApp to $phone'),
          ),
      ],
    );
  }
}
