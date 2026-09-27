// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'statement.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ShopTransaction _$ShopTransactionFromJson(Map<String, dynamic> json) => _ShopTransaction(
  id: json['id'] as String,
  transactionDate: DateTime.parse(json['transaction_date'] as String),
  voucherNumber: json['voucher_number'] as String?,
  voucherType: json['voucher_type'] as String?,
  category:
      $enumDecodeNullable(_$TxnCategoryEnumMap, json['category'], unknownValue: TxnCategory.adjustments) ??
      TxnCategory.adjustments,
  narration: json['narration'] as String?,
  debit: json['debit'] == null ? Money.zero : const MoneyConverter().fromJson(json['debit']),
  credit: json['credit'] == null ? Money.zero : const MoneyConverter().fromJson(json['credit']),
  amount: json['amount'] == null ? Money.zero : const MoneyConverter().fromJson(json['amount']),
  createdAt: json['created_at'] == null ? null : DateTime.parse(json['created_at'] as String),
);

Map<String, dynamic> _$ShopTransactionToJson(_ShopTransaction instance) => <String, dynamic>{
  'id': instance.id,
  'transaction_date': instance.transactionDate.toIso8601String(),
  'voucher_number': instance.voucherNumber,
  'voucher_type': instance.voucherType,
  'category': _$TxnCategoryEnumMap[instance.category]!,
  'narration': instance.narration,
  'debit': const MoneyConverter().toJson(instance.debit),
  'credit': const MoneyConverter().toJson(instance.credit),
  'amount': const MoneyConverter().toJson(instance.amount),
  'created_at': instance.createdAt?.toIso8601String(),
};

const _$TxnCategoryEnumMap = {
  TxnCategory.sales: 'sales',
  TxnCategory.receipts: 'receipts',
  TxnCategory.returns: 'returns',
  TxnCategory.adjustments: 'adjustments',
};
