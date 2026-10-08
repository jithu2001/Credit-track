import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/dashboard_models.dart';

part 'dashboard_repository.g.dart';

/// The dashboard from the WholeFlow app API in one call. For staff the totals
/// and top dues cover only their shops.
class DashboardRepository {
  DashboardRepository(this._api);

  final ApiClient _api;

  Future<Dashboard> load(String companyId) async {
    try {
      return Dashboard.fromJson(await _api.get('dashboard', {'company': companyId}));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
DashboardRepository dashboardRepository(Ref ref) => DashboardRepository(ref.watch(apiClientProvider));
