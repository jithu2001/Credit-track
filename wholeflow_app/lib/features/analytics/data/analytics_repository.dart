import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/money/money.dart';
import '../../../core/providers.dart';
import '../../shop_detail/domain/statement.dart';
import '../domain/payment_analysis.dart';

part 'analytics_repository.g.dart';

/// Everything the payment analysis needs for one company.
class AnalyticsData {
  const AnalyticsData({required this.shops, required this.txns, required this.booksFrom});

  final List<ShopOpening> shops;
  final List<PaymentTxn> txns;
  final DateTime booksFrom;
}

TxnCategory _category(Object? v) => switch (v) {
  'sales' => TxnCategory.sales,
  'receipts' => TxnCategory.receipts,
  'returns' => TxnCategory.returns,
  _ => TxnCategory.adjustments,
};

class AnalyticsRepository {
  AnalyticsRepository(this._client);

  final SupabaseClient _client;

  Future<AnalyticsData> load(String companyId) async {
    try {
      final company = await _client.from('tally_companies').select('books_from,period_from').eq('id', companyId).maybeSingle();
      final shopRows = await fetchAll(
        (from, to) => _client
            .from('shops')
            .select('id,name,phone,opening_balance_amount,opening_balance_type,receivable,sites(name)')
            .eq('company_id', companyId)
            .isFilter('deleted_at', null)
            .order('id')
            .range(from, to),
        pageSize: 1000,
      );
      final txnRows = await fetchAll(
        (from, to) => _client
            .from('transactions')
            .select('shop_id,transaction_date,voucher_type,voucher_number,category,debit,credit,created_at')
            .eq('company_id', companyId)
            .isFilter('deleted_at', null)
            .order('transaction_date')
            .order('created_at')
            .order('id')
            .range(from, to),
        pageSize: 1000,
      );

      final shops = [
        for (final r in shopRows)
          ShopOpening(
            id: r['id'] as String,
            name: r['name'] as String,
            siteName: (r['sites'] as Map?)?['name'] as String?,
            phone: r['phone'] as String?,
            opening: Money.fromSide(r['opening_balance_amount'], r['opening_balance_type'] as String?),
            receivable: Money.parse(r['receivable']),
          ),
      ];
      final txns = [
        for (final r in txnRows)
          PaymentTxn(
            shopId: r['shop_id'] as String,
            date: DateTime.parse(r['transaction_date'] as String),
            category: _category(r['category']),
            debit: Money.parse(r['debit']),
            credit: Money.parse(r['credit']),
            voucher: [r['voucher_type'], r['voucher_number']].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
            createdAt: r['created_at'] == null ? null : DateTime.parse(r['created_at'] as String),
          ),
      ];
      // Date the opening balance where the synced vouchers begin: the current
      // Tally period (the vouchers reconcile from there), else the first
      // voucher, else the start of the books. Dating it at books_from would
      // make balances carried forward look years old.
      final firstVoucher = txns.isEmpty ? null : txns.map((t) => t.date).reduce((a, b) => a.isBefore(b) ? a : b);
      final period = company?['period_from'] == null ? null : DateTime.parse(company!['period_from'] as String);
      final books = company?['books_from'] == null ? null : DateTime.parse(company!['books_from'] as String);
      final booksFrom = switch ((period, firstVoucher)) {
        (final p?, final f?) => p.isAfter(f) ? f : p,
        (final p?, null) => p,
        (null, final f?) => f,
        _ => books ?? DateTime.now(),
      };
      return AnalyticsData(shops: shops, txns: txns, booksFrom: booksFrom);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
AnalyticsRepository analyticsRepository(Ref ref) => AnalyticsRepository(ref.watch(supabaseProvider));
