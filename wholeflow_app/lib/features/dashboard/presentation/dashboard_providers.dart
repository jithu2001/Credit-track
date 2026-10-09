import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../shops/domain/shop.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_models.dart';

part 'dashboard_providers.g.dart';

/// The whole dashboard, fetched in one call; the providers below are its parts.
@riverpod
Future<Dashboard> dashboard(Ref ref, String companyId) => ref.watch(dashboardRepositoryProvider).load(companyId);

@riverpod
Future<CompanySummary?> companySummary(Ref ref, String companyId) async =>
    (await ref.watch(dashboardProvider(companyId).future)).summary;

@riverpod
Future<SyncState?> companySyncState(Ref ref, String companyId) async =>
    (await ref.watch(dashboardProvider(companyId).future)).syncState;

/// Null for staff who may not see the company's transactions.
@riverpod
Future<MonthSales?> monthSales(Ref ref, String companyId) async =>
    (await ref.watch(dashboardProvider(companyId).future)).monthSales;

@riverpod
Future<List<ShopSummary>> topDues(Ref ref, String companyId) async =>
    (await ref.watch(dashboardProvider(companyId).future)).topDues;
