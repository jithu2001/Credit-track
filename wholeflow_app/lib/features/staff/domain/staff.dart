import 'dart:math';

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../auth/domain/app_user.dart';
import '../../company/domain/company.dart';

part 'staff.freezed.dart';
part 'staff.g.dart';

/// A user of the business with their company assignments (owners have none).
@freezed
abstract class StaffMember with _$StaffMember {
  const StaffMember._();

  const factory StaffMember({
    required String id,
    required UserRole role,
    @Default('') String name,
    String? email,
    @Default(true) bool isActive,
    DateTime? createdAt,
    @JsonKey(includeFromJson: false, includeToJson: false) @Default(<CompanyAccess>[]) List<CompanyAccess> companies,
  }) = _StaffMember;

  factory StaffMember.fromJson(Map<String, dynamic> json) => _$StaffMemberFromJson(json);

  static const columns = 'id,role,name,email,is_active,created_at';

  bool get isOwner => role == UserRole.owner;
  bool get hasNoCompany => !isOwner && companies.isEmpty;
  String get displayName => name.trim().isNotEmpty ? name.trim() : (email ?? 'User');
}

/// One company in the staff form: what the owner is granting.
@freezed
abstract class CompanyGrant with _$CompanyGrant {
  const CompanyGrant._();

  const factory CompanyGrant({
    required String companyId,
    @Default(<String>{}) Set<String> areas,
    @Default(true) bool canViewTransactions,
  }) = _CompanyGrant;

  factory CompanyGrant.fromAccess(CompanyAccess a) =>
      CompanyGrant(companyId: a.companyId, areas: a.areas.toSet(), canViewTransactions: a.canViewTransactions);

  /// Body shape expected by the manage-staff function.
  Map<String, Object?> toRequest() => {
    'company_id': companyId,
    'areas': (areas.toList()..sort()),
    'can_view_transactions': canViewTransactions,
  };
}

/// "Ravi will see: JMJ Marketing (all areas), JK Tyres (Pala, Rajakkad; no transactions)".
String accessSummary(String name, List<CompanyGrant> grants, Map<String, String> companyNames) {
  final who = name.trim().isEmpty ? 'This staff member' : name.trim();
  if (grants.isEmpty) return "$who won't see any company's data.";
  final parts = [for (final g in grants) '${companyNames[g.companyId] ?? 'Unknown company'} (${describeGrant(g)})'];
  return '$who will see: ${parts.join(', ')}';
}

/// "all areas" / "Pala, Rajakkad; no transactions".
String describeGrant(CompanyGrant g) {
  final areas = g.areas.isEmpty
      ? 'all areas'
      : (g.areas.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))).join(', ');
  return g.canViewTransactions ? areas : '$areas; no transactions';
}

// No 0/O/1/l/I: passwords are read out or typed by hand.
const _passwordAlphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// A random initial password (Random.secure), with at least one digit.
String generatePassword({int length = 10, Random? random}) {
  final r = random ?? Random.secure();
  while (true) {
    final p = List.generate(length, (_) => _passwordAlphabet[r.nextInt(_passwordAlphabet.length)]).join();
    if (p.contains(RegExp(r'\d')) && p.contains(RegExp('[a-z]')) && p.contains(RegExp('[A-Z]'))) return p;
  }
}
