import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/providers.dart';
import '../domain/overdue_report.dart';

part 'overdue_repository.g.dart';

/// Shops past the credit period, aged on the server by `overdue_shops()`
/// (migration 0004), so staff who may not read transactions still get the
/// amounts and days. The function limits shops to the caller's areas and
/// leaves bills out when the caller may not see transactions.
class OverdueRepository {
  OverdueRepository(this._client);

  final SupabaseClient _client;

  Future<List<OverdueShop>> overdue(String companyId, {required int creditDays, required DateTime today}) async {
    final day =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    try {
      final rows = await fetchAll(
        (from, to) => _client
            .rpc('overdue_shops', params: {'p_company_id': companyId, 'p_credit_days': creditDays, 'p_today': day})
            .select(OverdueShop.columns)
            .order('shop_id', ascending: true)
            .range(from, to),
      );
      return rows.map(OverdueShop.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
OverdueRepository overdueRepository(Ref ref) => OverdueRepository(ref.watch(supabaseProvider));
