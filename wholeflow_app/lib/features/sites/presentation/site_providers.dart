import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../shops/domain/shop.dart';
import '../data/site_repository.dart';
import '../domain/site.dart';

part 'site_providers.g.dart';

/// Sites of a company the caller can see, A–Z.
@riverpod
Future<List<Site>> companySites(Ref ref, String companyId) => ref.watch(siteRepositoryProvider).sites(companyId);

/// Every visible site of the business (staff form: sites of each company).
@riverpod
Future<List<Site>> allSites(Ref ref) => ref.watch(siteRepositoryProvider).allSites();

enum SitesTab { sites, visits }

/// Which half of the owner's Sites tab shows. A view setting only.
@Riverpod(keepAlive: true)
class SitesTabController extends _$SitesTabController {
  @override
  SitesTab build() => SitesTab.sites;

  void set(SitesTab t) => state = t;
}

/// The period the Sites tab reports on. A view setting only: kept in memory.
@Riverpod(keepAlive: true)
class ReportPeriodController extends _$ReportPeriodController {
  @override
  ReportPeriod build() => ReportPeriod.thisMonth;

  void set(ReportPeriod p) => state = p;
}

/// Per-site figures for the chosen period.
@riverpod
Future<List<SiteReportRow>> siteReport(Ref ref, String companyId) {
  final (from, to) = ref.watch(reportPeriodControllerProvider).range(DateTime.now());
  return ref.watch(siteRepositoryProvider).report(companyId, from, to);
}

@riverpod
Future<List<ShopSummary>> siteShops(Ref ref, String siteId) => ref.watch(siteRepositoryProvider).siteShops(siteId);

/// All shops of a company with their current site, for the site editor.
@riverpod
Future<List<SiteShop>> companySiteShops(Ref ref, String companyId) => ref.watch(siteRepositoryProvider).companyShops(companyId);
