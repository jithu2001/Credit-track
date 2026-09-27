// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shop.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ShopSummary _$ShopSummaryFromJson(Map<String, dynamic> json) => _ShopSummary(
  id: _readShopId(json, 'id') as String,
  name: json['name'] as String,
  area: json['area'] as String?,
  phone: json['phone'] as String?,
  receivable: json['receivable'] == null ? Money.zero : const MoneyConverter().fromJson(json['receivable']),
);

Map<String, dynamic> _$ShopSummaryToJson(_ShopSummary instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'area': instance.area,
  'phone': instance.phone,
  'receivable': const MoneyConverter().toJson(instance.receivable),
};

_ShopDetail _$ShopDetailFromJson(Map<String, dynamic> json) => _ShopDetail(
  id: json['id'] as String,
  companyId: json['company_id'] as String,
  name: json['name'] as String,
  area: json['area'] as String?,
  phone: json['phone'] as String?,
  phones: (json['phones'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const <String>[],
  phoneSource: json['phone_source'] as String?,
  contactPerson: json['contact_person'] as String?,
  email: json['email'] as String?,
  gstin: json['gstin'] as String?,
  address: json['address'] as String?,
  addressLines: (json['address_lines'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const <String>[],
  state: json['state'] as String?,
  pincode: json['pincode'] as String?,
  openingBalanceAmount: json['opening_balance_amount'] == null
      ? Money.zero
      : const MoneyConverter().fromJson(json['opening_balance_amount']),
  openingBalanceType: json['opening_balance_type'] as String? ?? '',
  receivable: json['receivable'] == null ? Money.zero : const MoneyConverter().fromJson(json['receivable']),
  syncedAt: json['synced_at'] == null ? null : DateTime.parse(json['synced_at'] as String),
);

Map<String, dynamic> _$ShopDetailToJson(_ShopDetail instance) => <String, dynamic>{
  'id': instance.id,
  'company_id': instance.companyId,
  'name': instance.name,
  'area': instance.area,
  'phone': instance.phone,
  'phones': instance.phones,
  'phone_source': instance.phoneSource,
  'contact_person': instance.contactPerson,
  'email': instance.email,
  'gstin': instance.gstin,
  'address': instance.address,
  'address_lines': instance.addressLines,
  'state': instance.state,
  'pincode': instance.pincode,
  'opening_balance_amount': const MoneyConverter().toJson(instance.openingBalanceAmount),
  'opening_balance_type': instance.openingBalanceType,
  'receivable': const MoneyConverter().toJson(instance.receivable),
  'synced_at': instance.syncedAt?.toIso8601String(),
};
