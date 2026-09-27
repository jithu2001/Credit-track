import 'package:freezed_annotation/freezed_annotation.dart';

part 'company.freezed.dart';
part 'company.g.dart';

/// A Tally company (`tally_companies`). RLS returns only the companies the
/// caller may see: all of them for an owner, the assigned ones for staff.
@freezed
abstract class Company with _$Company {
  const factory Company({
    required String id,
    required String companyName,
    @Default('PENDING') String syncStatus,
    DateTime? lastSyncAt,
  }) = _Company;

  factory Company.fromJson(Map<String, dynamic> json) => _$CompanyFromJson(json);

  static const columns = 'id,company_name,sync_status,last_sync_at';
}

/// A row of `staff_company_access`: one company a staff member works for.
@freezed
abstract class CompanyAccess with _$CompanyAccess {
  const CompanyAccess._();

  const factory CompanyAccess({
    required String userId,
    required String companyId,
    @Default(<String>[]) List<String> areas,
    @Default(true) bool canViewTransactions,
  }) = _CompanyAccess;

  factory CompanyAccess.fromJson(Map<String, dynamic> json) => _$CompanyAccessFromJson(json);

  static const columns = 'user_id,company_id,areas,can_view_transactions';

  bool get allAreas => areas.isEmpty;
}
