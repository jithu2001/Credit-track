import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/providers.dart';
import '../../shops/domain/shop.dart';
import '../domain/site.dart';

/// Sites and their shops. Owners create, rename and delete sites directly
/// (RLS); which shops are in a site changes only through `set_site_shops`.
/// Staff read only the sites they have.
class SiteRepository {
  SiteRepository(this._client);

  final SupabaseClient _client;

  static final _day = DateFormat('yyyy-MM-dd');

  Future<List<Site>> sites(String companyId) async {
    try {
      final rows = await _client.from('sites').select(Site.columns).eq('company_id', companyId).order('name');
      return rows.map(Site.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Every site of the business the caller can see (for the staff form).
  Future<List<Site>> allSites() async {
    try {
      final rows = await _client.from('sites').select(Site.columns).order('name');
      return rows.map(Site.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Creates the site and puts [shopIds] in it; returns the new site id.
  Future<String> create(String companyId, String name, Set<String> shopIds) async {
    final String id;
    try {
      final row = await _client.from('sites').insert({'company_id': companyId, 'name': name.trim()}).select('id').single();
      id = row['id'] as String;
    } catch (e) {
      throw _nameFailure(e);
    }
    await setShops(id, shopIds);
    return id;
  }

  Future<void> rename(String siteId, String name) async {
    try {
      await _client.from('sites').update({'name': name.trim()}).eq('id', siteId);
    } catch (e) {
      throw _nameFailure(e);
    }
  }

  /// The site's shops leave it (they stay in the company); staff lose it.
  Future<void> delete(String siteId) async {
    try {
      await _client.from('sites').delete().eq('id', siteId);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Makes [shopIds] exactly the site's shops (moving them out of other sites).
  Future<void> setShops(String siteId, Set<String> shopIds) async {
    try {
      await _client.rpc('set_site_shops', params: {'p_site_id': siteId, 'p_shop_ids': shopIds.toList()});
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Every active shop of a company with its current site, for the site editor.
  Future<List<SiteShop>> companyShops(String companyId) async {
    try {
      final rows = await fetchAll(
        (from, to) => _client
            .from('shops')
            .select(SiteShop.columns)
            .eq('company_id', companyId)
            .isFilter('deleted_at', null)
            .order('name', ascending: true)
            .order('id', ascending: true)
            .range(from, to),
      );
      return rows.map(SiteShop.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// The shops of one site, highest balance first.
  Future<List<ShopSummary>> siteShops(String siteId) async {
    try {
      final rows = await fetchAll(
        (from, to) => _client
            .from('shops')
            .select(ShopSummary.shopColumns)
            .eq('site_id', siteId)
            .isFilter('deleted_at', null)
            .order('receivable', ascending: false)
            .order('id', ascending: true)
            .range(from, to),
      );
      return rows.map(ShopSummary.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<List<SiteReportRow>> report(String companyId, DateTime from, DateTime to) async {
    try {
      final rows = await _client.rpc(
        'site_report',
        params: {'p_company_id': companyId, 'p_from': _day.format(from), 'p_to': _day.format(to)},
      );
      return [for (final r in rows as List) SiteReportRow.fromJson(Map<String, dynamic>.from(r as Map))];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  static AppFailure _nameFailure(Object e) {
    if (e is PostgrestException && e.code == '23505') {
      return const AppFailure(FailureKind.invalidInput, 'There is already a site with this name in this company.');
    }
    if (e is PostgrestException && e.code == '23514') {
      return const AppFailure(FailureKind.invalidInput, 'Enter a site name (up to 80 characters).');
    }
    return AppFailure.from(e);
  }
}

final siteRepositoryProvider = Provider<SiteRepository>((ref) => SiteRepository(ref.watch(supabaseProvider)));
