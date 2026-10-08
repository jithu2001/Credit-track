import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../../company/domain/company.dart';
import '../domain/staff.dart';

part 'staff_repository.g.dart';

/// Staff management through the WholeFlow app API (owner only): the server
/// checks the caller, the companies and sites, and changes logins.
class StaffRepository {
  StaffRepository(this._api);

  final ApiClient _api;

  /// Owners first, then active staff, then disabled; A–Z within each (sorted on the server).
  Future<List<StaffMember>> members() async {
    try {
      final body = await _api.get('staff');
      return [
        for (final row in (body['staff'] as List).cast<Map<String, dynamic>>())
          StaffMember.fromJson(row).copyWith(
            companies: [
              for (final c in (row['companies'] as List? ?? const []).cast<Map<String, dynamic>>())
                CompanyAccess.fromJson(c).copyWith(siteIds: (c['site_ids'] as List? ?? const []).cast<String>()),
            ],
          ),
      ];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<String> createStaff({
    required String name,
    required String email,
    required String password,
    required List<CompanyGrant> companies,
    bool requiresCheckIn = false,
  }) async {
    try {
      final body = await _api.post('staff', {
        'name': name,
        'email': email,
        'password': password,
        'companies': [for (final c in companies) c.toRequest()],
        'requires_check_in': requiresCheckIn,
      });
      return body['id'] as String;
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> rename(String userId, String name) => _run(() => _api.patch('staff/$userId', {'name': name}));

  Future<void> setCompanies(String userId, List<CompanyGrant> companies) => _run(
    () => _api.put('staff/$userId/companies', {
      'companies': [for (final c in companies) c.toRequest()],
    }),
  );

  /// Whether the staff member must check in at shops on planned visit days.
  Future<void> setCheckIn(String userId, bool required) => _run(() => _api.put('staff/$userId/check-in', {'required': required}));

  Future<void> setActive(String userId, bool active) => _run(() => _api.put('staff/$userId/active', {'active': active}));

  Future<void> resetPassword(String userId, String password) =>
      _run(() => _api.post('staff/$userId/password', {'password': password}));

  Future<void> _run(Future<Object?> Function() call) async {
    try {
      await call();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
StaffRepository staffRepository(Ref ref) => StaffRepository(ref.watch(apiClientProvider));
