import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
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
