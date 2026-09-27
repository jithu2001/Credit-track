// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'company.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Company _$CompanyFromJson(Map<String, dynamic> json) => _Company(
  id: json['id'] as String,
  companyName: json['company_name'] as String,
  syncStatus: json['sync_status'] as String? ?? 'PENDING',
  lastSyncAt: json['last_sync_at'] == null ? null : DateTime.parse(json['last_sync_at'] as String),
);

Map<String, dynamic> _$CompanyToJson(_Company instance) => <String, dynamic>{
  'id': instance.id,
  'company_name': instance.companyName,
  'sync_status': instance.syncStatus,
  'last_sync_at': instance.lastSyncAt?.toIso8601String(),
};

_CompanyAccess _$CompanyAccessFromJson(Map<String, dynamic> json) => _CompanyAccess(
  userId: json['user_id'] as String,
  companyId: json['company_id'] as String,
  areas: (json['areas'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const <String>[],
  canViewTransactions: json['can_view_transactions'] as bool? ?? true,
);

Map<String, dynamic> _$CompanyAccessToJson(_CompanyAccess instance) => <String, dynamic>{
  'user_id': instance.userId,
  'company_id': instance.companyId,
  'areas': instance.areas,
  'can_view_transactions': instance.canViewTransactions,
};
