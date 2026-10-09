import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/purchase.dart';

/// Purchase bills from the WholeFlow app API (owner only).
class PurchaseRepository {
  PurchaseRepository(this._api);

  final ApiClient _api;

  static const pageSize = 50;

  /// One page of bills, newest first (search and supplier filter on the server).
  Future<List<PurchaseSummary>> page(PurchaseQuery query, int pageIndex) async {
    try {
      final body = await _api.get('purchases', {
        'company': query.companyId,
        'supplier': ?query.supplierId,
        if (query.search.trim().isNotEmpty) 'q': query.search.trim(),
        'page': '$pageIndex',
      });
      return [for (final r in (body['purchases'] as List).cast<Map<String, dynamic>>()) PurchaseSummary.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<PurchaseDetail> detail(String purchaseId) async {
    try {
      return PurchaseDetail.fromJson(await _api.get('purchases/$purchaseId'));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Monthly totals since [from] (first of a month), newest first, for the
  /// whole company or one supplier.
  Future<List<MonthPurchases>> monthTotals(String companyId, DateTime from, {String? supplierId}) async {
    try {
      final body = await _api.get('purchases/months', {
        'company': companyId,
        'from':
            '${from.year.toString().padLeft(4, '0')}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}',
        'supplier': ?supplierId,
      });
      return [for (final r in (body['months'] as List).cast<Map<String, dynamic>>()) MonthPurchases.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) => PurchaseRepository(ref.watch(apiClientProvider)));
