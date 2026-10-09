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
    @Default(false) bool requiresCheckIn,
    DateTime? createdAt,
    @JsonKey(includeFromJson: false, includeToJson: false) @Default(<CompanyAccess>[]) List<CompanyAccess> companies,
  }) = _StaffMember;

  factory StaffMember.fromJson(Map<String, dynamic> json) => _$StaffMemberFromJson(json);


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
    @Default(true) bool fullCompany,
    @Default(<String>{}) Set<String> siteIds,
    @Default(true) bool canViewTransactions,
  }) = _CompanyGrant;

  factory CompanyGrant.fromAccess(CompanyAccess a) => CompanyGrant(
    companyId: a.companyId,
    fullCompany: a.fullCompany,
    siteIds: a.fullCompany ? const {} : a.siteIds.toSet(),
    canViewTransactions: a.canViewTransactions,
  );

  /// Limited to sites, but none chosen: the server refuses this.
  bool get needsSites => !fullCompany && siteIds.isEmpty;

  /// Body shape expected by the manage-staff function.
  Map<String, Object?> toRequest() => {
    'company_id': companyId,
    'full_company': fullCompany,
    'site_ids': fullCompany ? const <String>[] : (siteIds.toList()..sort()),
    'can_view_transactions': canViewTransactions,
  };
}

/// "Ravi will see: JMJ Marketing (full company), JK Tyres (Town, Hills; no transactions)".
String accessSummary(String name, List<CompanyGrant> grants, Map<String, String> companyNames, Map<String, String> siteNames) {
  final who = name.trim().isEmpty ? 'This staff member' : name.trim();
  if (grants.isEmpty) return "$who won't see any company's data.";
  final parts = [for (final g in grants) '${companyNames[g.companyId] ?? 'Unknown company'} (${describeGrant(g, siteNames)})'];
  return '$who will see: ${parts.join(', ')}';
}

/// "full company" / "Town, Hills; no transactions".
String describeGrant(CompanyGrant g, Map<String, String> siteNames) {
  final sites = g.fullCompany
      ? 'full company'
      : g.siteIds.isEmpty
      ? 'no sites'
      : (g.siteIds.map((id) => siteNames[id] ?? 'Removed site').toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
            .join(', ');
  return g.canViewTransactions ? sites : '$sites; no transactions';
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
