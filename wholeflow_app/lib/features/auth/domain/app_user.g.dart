// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AppUser _$AppUserFromJson(Map<String, dynamic> json) => _AppUser(
  id: json['id'] as String,
  businessId: json['business_id'] as String,
  role: $enumDecode(_$UserRoleEnumMap, json['role']),
  name: json['name'] as String? ?? '',
  email: json['email'] as String?,
  isActive: json['is_active'] as bool? ?? true,
  requiresCheckIn: json['requires_check_in'] as bool? ?? false,
);

Map<String, dynamic> _$AppUserToJson(_AppUser instance) => <String, dynamic>{
  'id': instance.id,
  'business_id': instance.businessId,
  'role': _$UserRoleEnumMap[instance.role]!,
  'name': instance.name,
  'email': instance.email,
  'is_active': instance.isActive,
  'requires_check_in': instance.requiresCheckIn,
};

const _$UserRoleEnumMap = {UserRole.owner: 'OWNER', UserRole.staff: 'STAFF'};
