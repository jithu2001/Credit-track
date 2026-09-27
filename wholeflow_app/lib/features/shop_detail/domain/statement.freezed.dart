// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'statement.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ShopTransaction {

 String get id; DateTime get transactionDate; String? get voucherNumber; String? get voucherType;@JsonKey(unknownEnumValue: TxnCategory.adjustments) TxnCategory get category; String? get narration;@MoneyConverter() Money get debit;@MoneyConverter() Money get credit;/// Signed effect on receivable = debit - credit.
@MoneyConverter() Money get amount; DateTime? get createdAt;
/// Create a copy of ShopTransaction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShopTransactionCopyWith<ShopTransaction> get copyWith => _$ShopTransactionCopyWithImpl<ShopTransaction>(this as ShopTransaction, _$identity);

  /// Serializes this ShopTransaction to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ShopTransaction;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShopTransaction&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.transactionDate, _this.transactionDate) || other.transactionDate == _this.transactionDate)&&(identical(other.voucherNumber, _this.voucherNumber) || other.voucherNumber == _this.voucherNumber)&&(identical(other.voucherType, _this.voucherType) || other.voucherType == _this.voucherType)&&(identical(other.category, _this.category) || other.category == _this.category)&&(identical(other.narration, _this.narration) || other.narration == _this.narration)&&(identical(other.debit, _this.debit) || other.debit == _this.debit)&&(identical(other.credit, _this.credit) || other.credit == _this.credit)&&(identical(other.amount, _this.amount) || other.amount == _this.amount)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ShopTransaction;
  return Object.hash(runtimeType,_this.id,_this.transactionDate,_this.voucherNumber,_this.voucherType,_this.category,_this.narration,_this.debit,_this.credit,_this.amount,_this.createdAt);
}

@override
String toString() {
  final _this = this as ShopTransaction;
  return 'ShopTransaction(id: ${_this.id}, transactionDate: ${_this.transactionDate}, voucherNumber: ${_this.voucherNumber}, voucherType: ${_this.voucherType}, category: ${_this.category}, narration: ${_this.narration}, debit: ${_this.debit}, credit: ${_this.credit}, amount: ${_this.amount}, createdAt: ${_this.createdAt})';
}


}

/// @nodoc
abstract mixin class $ShopTransactionCopyWith<$Res>  {
  factory $ShopTransactionCopyWith(ShopTransaction value, $Res Function(ShopTransaction) _then) = _$ShopTransactionCopyWithImpl;
@useResult
$Res call({
 String id, DateTime transactionDate, String? voucherNumber, String? voucherType,@JsonKey(unknownEnumValue: TxnCategory.adjustments) TxnCategory category, String? narration,@MoneyConverter() Money debit,@MoneyConverter() Money credit,@MoneyConverter() Money amount, DateTime? createdAt
});




}
/// @nodoc
class _$ShopTransactionCopyWithImpl<$Res>
    implements $ShopTransactionCopyWith<$Res> {
  _$ShopTransactionCopyWithImpl(this._self, this._then);

  final ShopTransaction _self;
  final $Res Function(ShopTransaction) _then;

/// Create a copy of ShopTransaction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? transactionDate = null,Object? voucherNumber = freezed,Object? voucherType = freezed,Object? category = null,Object? narration = freezed,Object? debit = null,Object? credit = null,Object? amount = null,Object? createdAt = freezed,}) {
  return _then(ShopTransaction(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,transactionDate: null == transactionDate ? _self.transactionDate : transactionDate // ignore: cast_nullable_to_non_nullable
as DateTime,voucherNumber: freezed == voucherNumber ? _self.voucherNumber : voucherNumber // ignore: cast_nullable_to_non_nullable
as String?,voucherType: freezed == voucherType ? _self.voucherType : voucherType // ignore: cast_nullable_to_non_nullable
as String?,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as TxnCategory,narration: freezed == narration ? _self.narration : narration // ignore: cast_nullable_to_non_nullable
as String?,debit: null == debit ? _self.debit : debit // ignore: cast_nullable_to_non_nullable
as Money,credit: null == credit ? _self.credit : credit // ignore: cast_nullable_to_non_nullable
as Money,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as Money,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [ShopTransaction].
extension ShopTransactionPatterns on ShopTransaction {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShopTransaction value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShopTransaction() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShopTransaction value)  $default,){
final _that = this;
switch (_that) {
case _ShopTransaction():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShopTransaction value)?  $default,){
final _that = this;
switch (_that) {
case _ShopTransaction() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  DateTime transactionDate,  String? voucherNumber,  String? voucherType, @JsonKey(unknownEnumValue: TxnCategory.adjustments)  TxnCategory category,  String? narration, @MoneyConverter()  Money debit, @MoneyConverter()  Money credit, @MoneyConverter()  Money amount,  DateTime? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShopTransaction() when $default != null:
return $default(_that.id,_that.transactionDate,_that.voucherNumber,_that.voucherType,_that.category,_that.narration,_that.debit,_that.credit,_that.amount,_that.createdAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  DateTime transactionDate,  String? voucherNumber,  String? voucherType, @JsonKey(unknownEnumValue: TxnCategory.adjustments)  TxnCategory category,  String? narration, @MoneyConverter()  Money debit, @MoneyConverter()  Money credit, @MoneyConverter()  Money amount,  DateTime? createdAt)  $default,) {final _that = this;
switch (_that) {
case _ShopTransaction():
return $default(_that.id,_that.transactionDate,_that.voucherNumber,_that.voucherType,_that.category,_that.narration,_that.debit,_that.credit,_that.amount,_that.createdAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  DateTime transactionDate,  String? voucherNumber,  String? voucherType, @JsonKey(unknownEnumValue: TxnCategory.adjustments)  TxnCategory category,  String? narration, @MoneyConverter()  Money debit, @MoneyConverter()  Money credit, @MoneyConverter()  Money amount,  DateTime? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _ShopTransaction() when $default != null:
return $default(_that.id,_that.transactionDate,_that.voucherNumber,_that.voucherType,_that.category,_that.narration,_that.debit,_that.credit,_that.amount,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ShopTransaction implements ShopTransaction {
  const _ShopTransaction({required this.id, required this.transactionDate, this.voucherNumber, this.voucherType, @JsonKey(unknownEnumValue: TxnCategory.adjustments) this.category = TxnCategory.adjustments, this.narration, @MoneyConverter() this.debit = Money.zero, @MoneyConverter() this.credit = Money.zero, @MoneyConverter() this.amount = Money.zero, this.createdAt});
  factory _ShopTransaction.fromJson(Map<String, dynamic> json) => _$ShopTransactionFromJson(json);

@override final  String id;
@override final  DateTime transactionDate;
@override final  String? voucherNumber;
@override final  String? voucherType;
@override@JsonKey(unknownEnumValue: TxnCategory.adjustments) final  TxnCategory category;
@override final  String? narration;
@override@JsonKey()@MoneyConverter() final  Money debit;
@override@JsonKey()@MoneyConverter() final  Money credit;
/// Signed effect on receivable = debit - credit.
@override@JsonKey()@MoneyConverter() final  Money amount;
@override final  DateTime? createdAt;

/// Create a copy of ShopTransaction
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShopTransactionCopyWith<_ShopTransaction> get copyWith => __$ShopTransactionCopyWithImpl<_ShopTransaction>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ShopTransactionToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShopTransaction&&(identical(other.id, id) || other.id == id)&&(identical(other.transactionDate, transactionDate) || other.transactionDate == transactionDate)&&(identical(other.voucherNumber, voucherNumber) || other.voucherNumber == voucherNumber)&&(identical(other.voucherType, voucherType) || other.voucherType == voucherType)&&(identical(other.category, category) || other.category == category)&&(identical(other.narration, narration) || other.narration == narration)&&(identical(other.debit, debit) || other.debit == debit)&&(identical(other.credit, credit) || other.credit == credit)&&(identical(other.amount, amount) || other.amount == amount)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,transactionDate,voucherNumber,voucherType,category,narration,debit,credit,amount,createdAt);
}

@override
String toString() {
    return 'ShopTransaction(id: $id, transactionDate: $transactionDate, voucherNumber: $voucherNumber, voucherType: $voucherType, category: $category, narration: $narration, debit: $debit, credit: $credit, amount: $amount, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$ShopTransactionCopyWith<$Res> implements $ShopTransactionCopyWith<$Res> {
  factory _$ShopTransactionCopyWith(_ShopTransaction value, $Res Function(_ShopTransaction) _then) = __$ShopTransactionCopyWithImpl;
@override @useResult
$Res call({
 String id, DateTime transactionDate, String? voucherNumber, String? voucherType,@JsonKey(unknownEnumValue: TxnCategory.adjustments) TxnCategory category, String? narration,@MoneyConverter() Money debit,@MoneyConverter() Money credit,@MoneyConverter() Money amount, DateTime? createdAt
});




}
/// @nodoc
class __$ShopTransactionCopyWithImpl<$Res>
    implements _$ShopTransactionCopyWith<$Res> {
  __$ShopTransactionCopyWithImpl(this._self, this._then);

  final _ShopTransaction _self;
  final $Res Function(_ShopTransaction) _then;

/// Create a copy of ShopTransaction
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? transactionDate = null,Object? voucherNumber = freezed,Object? voucherType = freezed,Object? category = null,Object? narration = freezed,Object? debit = null,Object? credit = null,Object? amount = null,Object? createdAt = freezed,}) {
  return _then(_ShopTransaction(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,transactionDate: null == transactionDate ? _self.transactionDate : transactionDate // ignore: cast_nullable_to_non_nullable
as DateTime,voucherNumber: freezed == voucherNumber ? _self.voucherNumber : voucherNumber // ignore: cast_nullable_to_non_nullable
as String?,voucherType: freezed == voucherType ? _self.voucherType : voucherType // ignore: cast_nullable_to_non_nullable
as String?,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as TxnCategory,narration: freezed == narration ? _self.narration : narration // ignore: cast_nullable_to_non_nullable
as String?,debit: null == debit ? _self.debit : debit // ignore: cast_nullable_to_non_nullable
as Money,credit: null == credit ? _self.credit : credit // ignore: cast_nullable_to_non_nullable
as Money,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as Money,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
