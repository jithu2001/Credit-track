import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/balance_text.dart';
import '../../../core/widgets/states.dart';
import '../../shops/domain/shop.dart';
import '../domain/statement.dart';
import 'shop_detail_providers.dart';

/// Newest-first transactions with running balance, category and date filters.
class StatementView extends ConsumerStatefulWidget {
  const StatementView({super.key, required this.shop});

  final ShopDetail shop;

  @override
  ConsumerState<StatementView> createState() => _StatementViewState();
}

class _StatementViewState extends ConsumerState<StatementView> {
  final Set<TxnCategory> _categories = {};
  DateTimeRange? _range;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
      helpText: 'Show transactions between',
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final statement = ref.watch(shopStatementProvider(widget.shop.id));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(shopDetailProvider(widget.shop.id));
        ref.invalidate(shopStatementProvider(widget.shop.id));
        await ref.read(shopStatementProvider(widget.shop.id).future);
      },
      child: switch (statement) {
        AsyncValue(:final value?) => _buildList(context, value),
        AsyncValue(:final error?) => LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: c.maxHeight,
              child: ErrorState(error: error, onRetry: () => ref.invalidate(shopStatementProvider(widget.shop.id))),
            ),
          ),
        ),
        _ => const SkeletonList(),
      },
    );
  }

  Widget _buildList(BuildContext context, Statement s) {
    final lines = s.filtered(categories: _categories, from: _range?.start, to: _range?.end);
    final filtering = _categories.isNotEmpty || _range != null;
    final header = <Widget>[
      if (!s.reconciled) _ReconciliationWarning(statement: s),
      SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.s),
          children: [
            FilterChip(
              avatar: const Icon(Icons.date_range_rounded, size: 18),
              showCheckmark: false,
              label: Text(_range == null ? 'Any date' : '${formatDate(_range!.start)} – ${formatDate(_range!.end)}'),
              selected: _range != null,
              onSelected: (_) => _pickRange(),
              onDeleted: _range == null ? null : () => setState(() => _range = null),
            ),
            const SizedBox(width: Insets.s),
            for (final c in TxnCategory.values) ...[
              FilterChip(
                label: Text(c.label),
                selected: _categories.contains(c),
                onSelected: (on) => setState(() => on ? _categories.add(c) : _categories.remove(c)),
              ),
              const SizedBox(width: Insets.s),
            ],
          ],
        ),
      ),
      const Divider(height: 1),
    ];
    if (lines.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ...header,
          const SizedBox(height: Insets.xl),
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: filtering ? 'No transactions match' : 'No transactions yet',
            message: filtering ? 'Change the date range or categories.' : null,
          ),
        ],
      );
    }
    return ContentWidth(
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: header.length + lines.length + 1,
        itemBuilder: (context, i) {
          if (i < header.length) return header[i];
          final j = i - header.length;
          if (j == lines.length) {
            return Padding(
              padding: const EdgeInsets.all(Insets.l),
              child: Text(
                'Opening balance ${formatBalance(s.opening)}',
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            );
          }
          return Column(
            children: [
              _StatementRow(line: lines[j]),
              const Divider(height: 1, indent: Insets.l),
            ],
          );
        },
      ),
    );
  }
}

class _ReconciliationWarning extends StatelessWidget {
  const _ReconciliationWarning({required this.statement});

  final Statement statement;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.l, Insets.m, Insets.l, 0),
      child: Card.filled(
        color: semantic.warningContainer,
        child: Padding(
          padding: const EdgeInsets.all(Insets.m),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: semantic.onWarningContainer),
              const SizedBox(width: Insets.m),
              Expanded(
                child: Text(
                  "Transactions don't add up to the Tally balance (difference ${formatInr(statement.difference.abs())}). "
                  'The next sync usually fixes this.',
                  style: context.text.bodySmall?.copyWith(color: semantic.onWarningContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatementRow extends StatelessWidget {
  const _StatementRow({required this.line});

  final StatementLine line;

  @override
  Widget build(BuildContext context) {
    final t = line.transaction;
    final isDebit = t.debit.isPositive;
    final amount = isDebit ? t.debit : t.credit;
    final voucher = [t.voucherType, t.voucherNumber].where((s) => s != null && s.trim().isNotEmpty).join(' · ');
    final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatDate(t.transactionDate), style: context.text.titleSmall),
                if (voucher.isNotEmpty) Text(voucher, style: muted, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Insets.xs),
                _CategoryChip(category: t.category),
                if (t.narration?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: Insets.xs),
                  Text(t.narration!.trim(), style: muted, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: Insets.m),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Semantics(
                label: '${isDebit ? 'Debit' : 'Credit'} ${formatInr(amount)}',
                excludeSemantics: true,
                child: Text(
                  '${isDebit ? '+' : '−'} ${formatInr(amount)}',
                  style: context.text.titleSmall?.copyWith(
                    color: isDebit ? context.semantic.owed : context.semantic.credit,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(isDebit ? 'Debit' : 'Credit', style: muted),
              const SizedBox(height: Insets.xs),
              Text('Balance', style: muted),
              BalanceText(line.balanceAfter, style: context.text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final TxnCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.s, vertical: 2),
      decoration: BoxDecoration(color: context.colors.secondaryContainer, borderRadius: BorderRadius.circular(Insets.s)),
      child: Text(category.label, style: context.text.labelSmall?.copyWith(color: context.colors.onSecondaryContainer)),
    );
  }
}
