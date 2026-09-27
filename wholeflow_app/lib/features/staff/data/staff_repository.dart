import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/providers.dart';
import '../../company/domain/company.dart';
import '../domain/staff.dart';

part 'staff_repository.g.dart';

/// Reads users and assignments directly (RLS: owners see their business);
/// every change goes through the manage-staff Edge Function, which holds the
/// service-role key and checks that the caller is an active owner.
class StaffRepository {
  StaffRepository(this._client);

  final SupabaseClient _client;

  static const _function = 'manage-staff';

  Future<List<StaffMember>> members() async {
    try {
      final users = await _client.from('users').select(StaffMember.columns).order('created_at');
      final access = await _client.from('staff_company_access').select(CompanyAccess.columns);
      final byUser = <String, List<CompanyAccess>>{};
      for (final row in access) {
        final a = CompanyAccess.fromJson(row);
        byUser.putIfAbsent(a.userId, () => []).add(a);
      }
      final list = [for (final row in users) StaffMember.fromJson(row).copyWith(companies: byUser[row['id']] ?? const [])];
      // Owners first, then active staff, then disabled; A–Z within each.
      int rank(StaffMember m) => m.isOwner ? 0 : (m.isActive ? 1 : 2);
      list.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });
      return list;
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<String> createStaff({
    required String name,
    required String email,
    required String password,
    required List<CompanyGrant> companies,
  }) async {
    final data = await _invoke({
      'action': 'create_staff',
      'name': name,
      'email': email,
      'password': password,
      'companies': [for (final c in companies) c.toRequest()],
    });
    return (data as Map)['id'] as String;
  }

  Future<void> rename(String userId, String name) => _invoke({'action': 'update_staff', 'user_id': userId, 'name': name});

  Future<void> setCompanies(String userId, List<CompanyGrant> companies) => _invoke({
    'action': 'set_companies',
    'user_id': userId,
    'companies': [for (final c in companies) c.toRequest()],
  });

  Future<void> setActive(String userId, bool active) => _invoke({'action': 'set_active', 'user_id': userId, 'active': active});

  Future<void> resetPassword(String userId, String password) =>
      _invoke({'action': 'reset_password', 'user_id': userId, 'password': password});

  Future<Object?> _invoke(Map<String, Object?> body) async {
    try {
      final res = await _client.functions.invoke(_function, body: body);
      final data = res.data;
      return data is Map ? data['data'] : null;
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
StaffRepository staffRepository(Ref ref) => StaffRepository(ref.watch(supabaseProvider));
