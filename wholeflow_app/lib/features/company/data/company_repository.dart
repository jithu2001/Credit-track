import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/company.dart';

part 'company_repository.g.dart';

/// Companies, the caller's assignments and shop areas, from the app API.
class CompanyRepository {
  CompanyRepository(this._api);

  final ApiClient _api;

  Future<List<Company>> visibleCompanies() async {
    try {
      final body = await _api.get('companies');
      return [for (final r in (body['companies'] as List).cast<Map<String, dynamic>>()) Company.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// The caller's own assignments (staff); owners have none and need none.
  /// [userId] is the signed-in user: the server answers for them only.
  Future<List<CompanyAccess>> accessOf(String userId) async {
    try {
      final body = await _api.get('me/access');
      return [for (final r in (body['access'] as List).cast<Map<String, dynamic>>()) CompanyAccess.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Distinct Tally areas of a company's active shops, sorted (the site editor's "By area").
  Future<List<String>> areasOf(String companyId) async {
    try {
      final body = await _api.get('companies/$companyId/areas');
      return (body['areas'] as List).cast<String>();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
CompanyRepository companyRepository(Ref ref) => CompanyRepository(ref.watch(apiClientProvider));
