import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/payment_analysis.dart';

part 'analytics_repository.g.dart';

/// Payment insights from the WholeFlow app API (owner only; the server
/// refuses staff).
class AnalyticsRepository {
  AnalyticsRepository(this._api);

  final ApiClient _api;

  /// Company totals and one line per shop with bills.
  Future<BusinessPaymentSummary> summary(String companyId, {required int creditDays}) async {
    try {
      return BusinessPaymentSummary.fromJson(await _api.get('payments', {'company': companyId, 'credit_days': '$creditDays'}));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// One shop with its unpaid bills and its latest paid bills.
  Future<ShopPayments> shop(String shopId, {required int creditDays}) async {
    try {
      return ShopPayments.fromJson(await _api.get('payments/shops/$shopId', {'credit_days': '$creditDays'}));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
AnalyticsRepository analyticsRepository(Ref ref) => AnalyticsRepository(ref.watch(apiClientProvider));
