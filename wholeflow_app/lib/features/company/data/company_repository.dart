import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/providers.dart';
import '../domain/company.dart';

part 'company_repository.g.dart';

class CompanyRepository {
  CompanyRepository(this._client);

  final SupabaseClient _client;

  Future<List<Company>> visibleCompanies() async {
    try {
      final rows = await _client.from('tally_companies').select(Company.columns).order('company_name');
      return rows.map(Company.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// The caller's own assignments (staff); owners have none and need none.
  Future<List<CompanyAccess>> accessOf(String userId) async {
    try {
      final rows = await _client.from('staff_company_access').select(CompanyAccess.columns).eq('user_id', userId);
      return rows.map(CompanyAccess.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Distinct areas of a company's active shops, sorted (for filters and the staff form).
  Future<List<String>> areasOf(String companyId) async {
    try {
      final rows = await fetchAll(
        (from, to) => _client
            .from('shops')
            .select('area')
            .eq('company_id', companyId)
            .isFilter('deleted_at', null)
            .not('area', 'is', null)
            .order('area')
            .range(from, to),
        pageSize: 1000,
      );
      // Exact values: the shop list filters with `area in (...)`.
      final areas = <String>{
        for (final r in rows)
          if ((r['area'] as String?)?.isNotEmpty ?? false) r['area'] as String,
      };
      return areas.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
CompanyRepository companyRepository(Ref ref) => CompanyRepository(ref.watch(supabaseProvider));
