import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../../shops/domain/shop.dart';
import '../domain/site.dart';

/// Sites and their shops, from the app API. Owners create, rename and delete
/// sites; which shops are in a site changes only through `set_site_shops`
/// (the server's database rules decide who may). Staff read only their sites.
class SiteRepository {
  SiteRepository(this._api);

  final ApiClient _api;

  static final _day = DateFormat('yyyy-MM-dd');

  List<Site> _sites(Map<String, dynamic> body) => [
    for (final r in (body['sites'] as List).cast<Map<String, dynamic>>()) Site.fromJson(r),
  ];

  Future<List<Site>> sites(String companyId) async {
    try {
      return _sites(await _api.get('sites', {'company': companyId}));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Every site of the business the caller can see (for the staff form).
  Future<List<Site>> allSites() async {
    try {
      return _sites(await _api.get('sites'));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Creates the site with [shopIds] in it; returns the new site id.
  Future<String> create(String companyId, String name, Set<String> shopIds) async {
    try {
      final body = await _api.post('sites', {'company': companyId, 'name': name.trim(), 'shops': shopIds.toList()});
      return body['id'] as String;
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> rename(String siteId, String name) async {
    try {
      await _api.patch('sites/$siteId', {'name': name.trim()});
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// The site's shops leave it (they stay in the company); staff lose it.
  Future<void> delete(String siteId) async {
    try {
      await _api.delete('sites/$siteId');
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Makes [shopIds] exactly the site's shops (moving them out of other sites).
  Future<void> setShops(String siteId, Set<String> shopIds) async {
    try {
      await _api.put('sites/$siteId/shops', {'shops': shopIds.toList()});
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Every active shop of a company with its current site, for the site editor.
  Future<List<SiteShop>> companyShops(String companyId) async {
    try {
      final body = await _api.get('companies/$companyId/site-shops');
      return [for (final r in (body['shops'] as List).cast<Map<String, dynamic>>()) SiteShop.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// The shops of one site, highest balance first.
  Future<List<ShopSummary>> siteShops(String siteId) async {
    try {
      final body = await _api.get('sites/$siteId/shops');
      return [for (final r in (body['shops'] as List).cast<Map<String, dynamic>>()) ShopSummary.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<List<SiteReportRow>> report(String companyId, DateTime from, DateTime to) async {
    try {
      final body = await _api.get('reports/sites', {'company': companyId, 'from': _day.format(from), 'to': _day.format(to)});
      return [for (final r in (body['rows'] as List).cast<Map<String, dynamic>>()) SiteReportRow.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

final siteRepositoryProvider = Provider<SiteRepository>((ref) => SiteRepository(ref.watch(apiClientProvider)));
