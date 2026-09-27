import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../shops/data/shop_repository.dart';
import '../../shops/domain/shop.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_models.dart';

part 'dashboard_providers.g.dart';

@riverpod
Future<CompanySummary?> companySummary(Ref ref, String companyId) => ref.watch(dashboardRepositoryProvider).summary(companyId);

@riverpod
Future<SyncState?> companySyncState(Ref ref, String companyId) => ref.watch(dashboardRepositoryProvider).syncState(companyId);

@riverpod
Future<MonthSales> monthSales(Ref ref, String companyId) =>
    ref.watch(dashboardRepositoryProvider).monthSales(companyId, DateTime.now());

@riverpod
Future<List<ShopSummary>> topDues(Ref ref, String companyId) => ref.watch(shopRepositoryProvider).topDues(companyId);
