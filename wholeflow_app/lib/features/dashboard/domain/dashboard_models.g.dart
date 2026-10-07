// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CompanySummary _$CompanySummaryFromJson(Map<String, dynamic> json) =>
    _CompanySummary(
      companyId: json['company_id'] as String,
      companyName: json['company_name'] as String,
      shops: (json['shops'] as num?)?.toInt() ?? 0,
      shopsWithDues: (json['shops_with_dues'] as num?)?.toInt() ?? 0,
      totalOutstanding: json['total_outstanding'] == null
          ? Money.zero
          : const MoneyConverter().fromJson(json['total_outstanding']),
      totalCredit: json['total_credit'] == null
          ? Money.zero
          : const MoneyConverter().fromJson(json['total_credit']),
    );

Map<String, dynamic> _$CompanySummaryToJson(
  _CompanySummary instance,
) => <String, dynamic>{
  'company_id': instance.companyId,
  'company_name': instance.companyName,
  'shops': instance.shops,
  'shops_with_dues': instance.shopsWithDues,
  'total_outstanding': const MoneyConverter().toJson(instance.totalOutstanding),
  'total_credit': const MoneyConverter().toJson(instance.totalCredit),
};

_SyncState _$SyncStateFromJson(Map<String, dynamic> json) => _SyncState(
  lastSuccessfulSyncAt: json['last_successful_sync_at'] == null
      ? null
      : DateTime.parse(json['last_successful_sync_at'] as String),
  lastAttemptAt: json['last_attempt_at'] == null
      ? null
      : DateTime.parse(json['last_attempt_at'] as String),
  status: json['status'] as String? ?? 'ok',
  errorCode: json['error_code'] as String?,
  errorMessage: json['error_message'] as String?,
);

Map<String, dynamic> _$SyncStateToJson(
  _SyncState instance,
) => <String, dynamic>{
  'last_successful_sync_at': instance.lastSuccessfulSyncAt?.toIso8601String(),
  'last_attempt_at': instance.lastAttemptAt?.toIso8601String(),
  'status': instance.status,
  'error_code': instance.errorCode,
  'error_message': instance.errorMessage,
};
