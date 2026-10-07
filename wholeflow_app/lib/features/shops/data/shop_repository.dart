import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/providers.dart';
import '../domain/shop.dart';

part 'shop_repository.g.dart';

/// Removes characters that would break a PostgREST `or=(...)` filter.
String sanitizeSearch(String raw) => raw.replaceAll(RegExp(r'[,()*%\\"]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

class ShopRepository {
  ShopRepository(this._client);

  final SupabaseClient _client;

  static const pageSize = 50;

  /// One page of the shop list. RLS limits staff to their sites.
  Future<List<ShopSummary>> page(String companyId, ShopFilter filter, int pageIndex) async {
    try {
      var q = _client.from('shops').select(ShopSummary.shopColumns).eq('company_id', companyId).isFilter('deleted_at', null);
      final search = sanitizeSearch(filter.query);
      if (search.isNotEmpty) {
        q = q.or('name.ilike.*$search*,phone.ilike.*$search*,area.ilike.*$search*');
      }
      q = switch (filter.balance) {
        BalanceFilter.all => q,
        BalanceFilter.owes => q.gt('receivable', 0),
        BalanceFilter.credit => q.lt('receivable', 0),
        BalanceFilter.settled => q.eq('receivable', 0),
      };
      if (filter.siteIds.isNotEmpty) {
        final ids = filter.siteIds.where((id) => id != ShopFilter.noSite).toList();
        final noSite = filter.siteIds.contains(ShopFilter.noSite);
        q = switch ((ids.isEmpty, noSite)) {
          (true, _) => q.isFilter('site_id', null),
          (false, false) => q.inFilter('site_id', ids),
          (false, true) => q.or('site_id.in.(${ids.join(',')}),site_id.is.null'),
        };
      }
      final sorted = switch (filter.sort) {
        // "High to low" means the biggest amount first; credits are negative,
        // so under the In credit filter that is the most negative first.
        ShopSort.balanceDesc =>
          q.order('receivable', ascending: filter.balance == BalanceFilter.credit).order('name', ascending: true),
        ShopSort.balanceAsc =>
          q.order('receivable', ascending: filter.balance != BalanceFilter.credit).order('name', ascending: true),
        ShopSort.name => q.order('name', ascending: true),
      };
      final from = pageIndex * pageSize;
      final rows = await sorted.range(from, from + pageSize - 1);
      return rows.map(ShopSummary.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<ShopDetail> detail(String shopId) async {
    try {
      final row = await _client
          .from('shops')
          .select(ShopDetail.columns)
          .eq('id', shopId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) throw const AppFailure(FailureKind.notFound, 'This shop is not available.');
      return ShopDetail.fromJson(row);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<List<ShopSummary>> topDues(String companyId, {int limit = 10}) async {
    try {
      final rows = await _client
          .from('v_shop_outstanding')
          .select(ShopSummary.viewColumns)
          .eq('company_id', companyId)
          .gt('receivable', 0)
          .order('receivable', ascending: false)
          .limit(limit);
      return rows.map(ShopSummary.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Every shop that owes the business, for the outstanding report.
  Future<List<ShopSummary>> outstanding(String companyId) async {
    try {
      final rows = await fetchAll(
        (from, to) => _client
            .from('v_shop_outstanding')
            .select(ShopSummary.viewColumns)
            .eq('company_id', companyId)
            .gt('receivable', 0)
            .order('receivable', ascending: false)
            .order('shop_id', ascending: true)
            .range(from, to),
      );
      return rows.map(ShopSummary.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
ShopRepository shopRepository(Ref ref) => ShopRepository(ref.watch(supabaseProvider));
