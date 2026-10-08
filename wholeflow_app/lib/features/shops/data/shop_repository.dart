import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/api/api_client.dart';
import '../../outstanding/domain/outstanding_report.dart';
import '../domain/shop.dart';

part 'shop_repository.g.dart';

/// Shops from the WholeFlow app API. Row-level security on the server
/// limits staff to their sites.
class ShopRepository {
  ShopRepository(this._api);

  final ApiClient _api;

  static const pageSize = 50;

  static const _sorts = {ShopSort.balanceDesc: 'balance_desc', ShopSort.balanceAsc: 'balance_asc', ShopSort.name: 'name'};

  /// One page of the shop list (search, balance, sites and sort on the server).
  Future<List<ShopSummary>> page(String companyId, ShopFilter filter, int pageIndex) async {
    try {
      final body = await _api.get('shops', {
        'company': companyId,
        if (filter.query.trim().isNotEmpty) 'q': filter.query.trim(),
        'balance': filter.balance.name,
        if (filter.siteIds.isNotEmpty) 'sites': filter.siteIds.join(','),
        'sort': _sorts[filter.sort]!,
        'page': '$pageIndex',
      });
      return [for (final r in (body['shops'] as List).cast<Map<String, dynamic>>()) ShopSummary.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<ShopDetail> detail(String shopId) async {
    try {
      return ShopDetail.fromJson(await _api.get('shops/$shopId'));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Every shop that owes the business, grouped by site on the server.
  Future<OutstandingReport> outstandingReport(String companyId) async {
    try {
      return OutstandingReport.fromJson(await _api.get('reports/outstanding', {'company': companyId}));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
ShopRepository shopRepository(Ref ref) => ShopRepository(ref.watch(apiClientProvider));
