import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/providers.dart';
import '../../shops/data/shop_repository.dart' show sanitizeSearch;
import '../domain/purchase.dart';

/// Purchase bills. RLS returns them to the owner only.
class PurchaseRepository {
  PurchaseRepository(this._client);

  final SupabaseClient _client;

  static const pageSize = 50;

  /// One page of bills, newest first.
  Future<List<PurchaseSummary>> page(PurchaseQuery query, int pageIndex) async {
    try {
      var q = _client
          .from('purchases')
          .select(PurchaseSummary.columns)
          .eq('company_id', query.companyId)
          .isFilter('deleted_at', null);
      if (query.supplierId != null) q = q.eq('supplier_id', query.supplierId!);
      final search = sanitizeSearch(query.search);
      if (search.isNotEmpty) {
        q = q.or('supplier_name.ilike.*$search*,voucher_number.ilike.*$search*,supplier_bill_number.ilike.*$search*');
      }
      final from = pageIndex * pageSize;
      final rows = await q
          .order('purchase_date', ascending: false)
          .order('tally_alter_id', ascending: false)
          .order('id', ascending: true)
          .range(from, from + pageSize - 1);
      return rows.map(PurchaseSummary.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<PurchaseDetail> detail(String purchaseId) async {
    try {
      final row = await _client
          .from('purchases')
          .select(PurchaseDetail.columns)
          .eq('id', purchaseId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) throw const AppFailure(FailureKind.notFound, 'This purchase bill is not available.');
      return PurchaseDetail.fromJson(row);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Monthly totals since [from] (first of a month), for the whole company or
  /// one supplier.
  Future<List<MonthPurchases>> monthTotals(String companyId, DateTime from, {String? supplierId}) async {
    try {
      final rows = await fetchAll((start, end) {
        var q = _client
            .from('v_purchases_by_supplier_month')
            .select('month,bills,total_amount')
            .eq('company_id', companyId)
            .gte('month', _isoDate(from));
        if (supplierId != null) q = q.eq('supplier_id', supplierId);
        return q
            .order('month', ascending: false)
            .order('supplier_name', ascending: true)
            .order('supplier_id', ascending: true)
            .range(start, end);
      });
      return monthTotalsOf(rows);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) => PurchaseRepository(ref.watch(supabaseProvider)));
