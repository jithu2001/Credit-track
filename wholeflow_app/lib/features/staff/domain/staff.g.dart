// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'staff.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_StaffMember _$StaffMemberFromJson(Map<String, dynamic> json) => _StaffMember(
  id: json['id'] as String,
  role: $enumDecode(_$UserRoleEnumMap, json['role']),
  name: json['name'] as String? ?? '',
  email: json['email'] as String?,
  isActive: json['is_active'] as bool? ?? true,
  requiresCheckIn: json['requires_check_in'] as bool? ?? false,
  createdAt: json['created_at'] == null ? null : DateTime.parse(json['created_at'] as String),
);

Map<String, dynamic> _$StaffMemberToJson(_StaffMember instance) => <String, dynamic>{
  'id': instance.id,
  'role': _$UserRoleEnumMap[instance.role]!,
  'name': instance.name,
  'email': instance.email,
  'is_active': instance.isActive,
  'requires_check_in': instance.requiresCheckIn,
  'created_at': instance.createdAt?.toIso8601String(),
};

const _$UserRoleEnumMap = {UserRole.owner: 'OWNER', UserRole.staff: 'STAFF'};
