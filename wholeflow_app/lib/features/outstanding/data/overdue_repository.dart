import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/overdue_report.dart';

part 'overdue_repository.g.dart';

/// Shops past the credit period from the WholeFlow app API: aged by the
/// database's `overdue_shops()` and grouped by site on the server. Staff get
/// only their sites, and no bills when they may not see transactions.
class OverdueRepository {
  OverdueRepository(this._api);

  final ApiClient _api;

  Future<OverdueReport> report(String companyId, {required int creditDays}) async {
    try {
      return OverdueReport.fromJson(await _api.get('reports/overdue', {'company': companyId, 'credit_days': '$creditDays'}));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
OverdueRepository overdueRepository(Ref ref) => OverdueRepository(ref.watch(apiClientProvider));
