import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/providers.dart';
import '../domain/statement.dart';

part 'transaction_repository.g.dart';

class TransactionRepository {
  TransactionRepository(this._client);

  final SupabaseClient _client;

  /// All active transactions of a shop, fetched in pages. The full set is
  /// needed for running balances and the reconciliation check; a shop has
  /// hundreds of vouchers at most. RLS returns none when the staff member may
  /// not view transactions for this company.
  Future<List<ShopTransaction>> forShop(String shopId) async {
    try {
      final rows = await fetchAll(
        (from, to) => _client
            .from('transactions')
            .select(ShopTransaction.columns)
            .eq('shop_id', shopId)
            .isFilter('deleted_at', null)
            .order('transaction_date', ascending: false)
            .order('created_at', ascending: false)
            .order('id', ascending: true)
            .range(from, to),
      );
      return rows.map(ShopTransaction.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
TransactionRepository transactionRepository(Ref ref) => TransactionRepository(ref.watch(supabaseProvider));
