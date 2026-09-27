import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/money/money.dart';
import '../../../core/providers.dart';
import '../domain/dashboard_models.dart';

part 'dashboard_repository.g.dart';

class DashboardRepository {
  DashboardRepository(this._client);

  final SupabaseClient _client;

  Future<CompanySummary?> summary(String companyId) async {
    try {
      final row = await _client
          .from('v_company_summary')
          .select(CompanySummary.columns)
          .eq('company_id', companyId)
          .maybeSingle();
      return row == null ? null : CompanySummary.fromJson(row);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Sum of `sales` transactions (debits) dated in the month of [now]. RLS
  /// limits staff to their shops; PostgREST has no aggregates here, so the
  /// month's rows are summed on the device.
  Future<MonthSales> monthSales(String companyId, DateTime now) async {
    final month = DateTime(now.year, now.month);
    final next = DateTime(now.year, now.month + 1);
    String day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-01';
    try {
      final rows = await fetchAll(
        (from, to) => _client
            .from('transactions')
            .select('id,debit')
            .eq('company_id', companyId)
            .eq('category', 'sales')
            .isFilter('deleted_at', null)
            .gte('transaction_date', day(month))
            .lt('transaction_date', day(next))
            .gt('debit', 0)
            .order('id')
            .range(from, to),
        pageSize: 1000,
      );
      final amount = rows.fold(Money.zero, (sum, r) => sum + Money.parse(r['debit']));
      return MonthSales(month: month, amount: amount, bills: rows.length);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<SyncState?> syncState(String companyId) async {
    try {
      final row = await _client
          .from('sync_state')
          .select(SyncState.columns)
          .eq('company_id', companyId)
          .eq('entity_type', 'company')
          .maybeSingle();
      return row == null ? null : SyncState.fromJson(row);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
DashboardRepository dashboardRepository(Ref ref) => DashboardRepository(ref.watch(supabaseProvider));
