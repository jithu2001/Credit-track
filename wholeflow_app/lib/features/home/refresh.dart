import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analytics/presentation/analytics_providers.dart';
import '../auth/presentation/session_controller.dart';
import '../company/presentation/company_providers.dart';
import '../dashboard/presentation/dashboard_providers.dart';
import '../inventory/presentation/inventory_providers.dart';
import '../outstanding/presentation/outstanding_views.dart';
import '../purchases/presentation/purchase_providers.dart';
import '../shop_detail/presentation/shop_detail_providers.dart';
import '../shops/presentation/shop_list_controller.dart';
import '../sites/presentation/site_providers.dart';
import '../subscription/presentation/subscription_providers.dart';
import '../suppliers/presentation/supplier_providers.dart';
import '../visits/presentation/location_providers.dart';
import '../visits/presentation/visit_providers.dart';

/// Pull-to-refresh, app resume and the dashboard timer all come here: re-check
/// the account (a disabled user is signed out), reload the visible companies
/// (an owner may have changed this staff member's assignments) and every
/// company-scoped list.
Future<void> refreshCompanyData(WidgetRef ref) async {
  unawaited(ref.read(sessionControllerProvider.notifier).revalidate());
  ref
    ..invalidate(serviceStatusProvider)
    ..invalidate(companiesProvider)
    ..invalidate(myAccessProvider)
    ..invalidate(companyAreasProvider)
    ..invalidate(companySitesProvider)
    ..invalidate(allSitesProvider)
    ..invalidate(siteReportProvider)
    ..invalidate(siteShopsProvider)
    ..invalidate(companySiteShopsProvider)
    ..invalidate(companySummaryProvider)
    ..invalidate(companySyncStateProvider)
    ..invalidate(topDuesProvider)
    ..invalidate(monthSalesProvider)
    ..invalidate(shopListProvider)
    ..invalidate(outstandingReportProvider)
    ..invalidate(overdueReportProvider)
    ..invalidate(shopDetailProvider)
    ..invalidate(shopStatementProvider)
    ..invalidate(analyticsDataProvider)
    ..invalidate(stockItemsProvider)
    ..invalidate(stockItemProvider)
    ..invalidate(itemPurchasesProvider)
    ..invalidate(purchaseListProvider)
    ..invalidate(purchaseDetailProvider)
    ..invalidate(recentMonthsProvider)
    ..invalidate(supplierMonthsProvider)
    ..invalidate(suppliersProvider)
    ..invalidate(supplierDetailProvider)
    ..invalidate(pendingSuggestionsProvider)
    ..invalidate(shopLocationProvider)
    ..invalidate(companyDayTasksProvider)
    ..invalidate(myTodayTasksProvider)
    ..invalidate(myHistoryProvider)
    ..invalidate(staffHistoryProvider)
    ..invalidate(visitPlansProvider);
  try {
    final company = await ref.read(activeCompanyProvider.future);
    if (company != null) await ref.read(companySummaryProvider(company.id).future);
  } catch (_) {
    // Screens show their own error states.
  }
}
