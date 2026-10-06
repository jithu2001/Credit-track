import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_user.freezed.dart';
part 'app_user.g.dart';

enum UserRole {
  @JsonValue('OWNER')
  owner('Owner'),
  @JsonValue('STAFF')
  staff('Staff');

  const UserRole(this.label);
  final String label;
}

/// A row of `public.users`: a login account tied to a business.
@freezed
abstract class AppUser with _$AppUser {
  const AppUser._();

  const factory AppUser({
    required String id,
    required String businessId,
    required UserRole role,
    @Default('') String name,
    String? email,
    @Default(true) bool isActive,

    /// Staff who check in at shops on planned visit days (they get a Visits tab).
    @Default(false) bool requiresCheckIn,
  }) = _AppUser;

  factory AppUser.fromJson(Map<String, dynamic> json) => _$AppUserFromJson(json);

  static const columns = 'id,business_id,role,name,email,is_active,requires_check_in';

  bool get isOwner => role == UserRole.owner;

  String get displayName => name.trim().isNotEmpty ? name.trim() : (email ?? 'User');
}
