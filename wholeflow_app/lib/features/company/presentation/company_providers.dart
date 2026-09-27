import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/company_repository.dart';
import '../domain/company.dart';

part 'company_providers.g.dart';

const _selectedCompanyKey = 'selected_company_id';

/// Companies the signed-in user can see (RLS-filtered). Reloaded per user.
@Riverpod(keepAlive: true)
Future<List<Company>> companies(Ref ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(companyRepositoryProvider).visibleCompanies();
}

/// The staff member's assignments keyed by company id; empty for owners.
@Riverpod(keepAlive: true)
Future<Map<String, CompanyAccess>> myAccess(Ref ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null || user.isOwner) return const {};
  final rows = await ref.watch(companyRepositoryProvider).accessOf(user.id);
  return {for (final a in rows) a.companyId: a};
}

/// The remembered company choice (may point to a company no longer visible).
@Riverpod(keepAlive: true)
class SelectedCompanyId extends _$SelectedCompanyId {
  @override
  String? build() => ref.watch(sharedPreferencesProvider).getString(_selectedCompanyKey);

  Future<void> select(String id) async {
    state = id;
    await ref.read(sharedPreferencesProvider).setString(_selectedCompanyKey, id);
  }
}

/// The company every data screen is scoped to: the remembered one if still
/// visible, otherwise the first. Null when the user can see no company.
@Riverpod(keepAlive: true)
Future<Company?> activeCompany(Ref ref) async {
  final list = await ref.watch(companiesProvider.future);
  if (list.isEmpty) return null;
  final saved = ref.watch(selectedCompanyIdProvider);
  return list.firstWhere((c) => c.id == saved, orElse: () => list.first);
}

/// Whether the Statement tab is shown for [companyId].
@riverpod
bool canViewTransactions(Ref ref, String companyId) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  if (user.isOwner) return true;
  final access = ref.watch(myAccessProvider).value;
  return access?[companyId]?.canViewTransactions ?? false;
}

/// Distinct shop areas of a company.
@riverpod
Future<List<String>> companyAreas(Ref ref, String companyId) => ref.watch(companyRepositoryProvider).areasOf(companyId);
