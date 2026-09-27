// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'shop.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ShopSummary {

@JsonKey(readValue: _readShopId) String get id; String get name; String? get area; String? get phone;@MoneyConverter() Money get receivable;
/// Create a copy of ShopSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShopSummaryCopyWith<ShopSummary> get copyWith => _$ShopSummaryCopyWithImpl<ShopSummary>(this as ShopSummary, _$identity);

  /// Serializes this ShopSummary to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ShopSummary;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShopSummary&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.area, _this.area) || other.area == _this.area)&&(identical(other.phone, _this.phone) || other.phone == _this.phone)&&(identical(other.receivable, _this.receivable) || other.receivable == _this.receivable));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ShopSummary;
  return Object.hash(runtimeType,_this.id,_this.name,_this.area,_this.phone,_this.receivable);
}

@override
String toString() {
  final _this = this as ShopSummary;
  return 'ShopSummary(id: ${_this.id}, name: ${_this.name}, area: ${_this.area}, phone: ${_this.phone}, receivable: ${_this.receivable})';
}


}

/// @nodoc
abstract mixin class $ShopSummaryCopyWith<$Res>  {
  factory $ShopSummaryCopyWith(ShopSummary value, $Res Function(ShopSummary) _then) = _$ShopSummaryCopyWithImpl;
@useResult
$Res call({
@JsonKey(readValue: _readShopId) String id, String name, String? area, String? phone,@MoneyConverter() Money receivable
});




}
/// @nodoc
class _$ShopSummaryCopyWithImpl<$Res>
    implements $ShopSummaryCopyWith<$Res> {
  _$ShopSummaryCopyWithImpl(this._self, this._then);

  final ShopSummary _self;
  final $Res Function(ShopSummary) _then;

/// Create a copy of ShopSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? area = freezed,Object? phone = freezed,Object? receivable = null,}) {
  return _then(ShopSummary(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,area: freezed == area ? _self.area : area // ignore: cast_nullable_to_non_nullable
as String?,phone: freezed == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String?,receivable: null == receivable ? _self.receivable : receivable // ignore: cast_nullable_to_non_nullable
as Money,
  ));
}

}


/// Adds pattern-matching-related methods to [ShopSummary].
extension ShopSummaryPatterns on ShopSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShopSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShopSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShopSummary value)  $default,){
final _that = this;
switch (_that) {
case _ShopSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShopSummary value)?  $default,){
final _that = this;
switch (_that) {
case _ShopSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(readValue: _readShopId)  String id,  String name,  String? area,  String? phone, @MoneyConverter()  Money receivable)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShopSummary() when $default != null:
return $default(_that.id,_that.name,_that.area,_that.phone,_that.receivable);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(readValue: _readShopId)  String id,  String name,  String? area,  String? phone, @MoneyConverter()  Money receivable)  $default,) {final _that = this;
switch (_that) {
case _ShopSummary():
return $default(_that.id,_that.name,_that.area,_that.phone,_that.receivable);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(readValue: _readShopId)  String id,  String name,  String? area,  String? phone, @MoneyConverter()  Money receivable)?  $default,) {final _that = this;
switch (_that) {
case _ShopSummary() when $default != null:
return $default(_that.id,_that.name,_that.area,_that.phone,_that.receivable);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ShopSummary implements ShopSummary {
  const _ShopSummary({@JsonKey(readValue: _readShopId) required this.id, required this.name, this.area, this.phone, @MoneyConverter() this.receivable = Money.zero});
  factory _ShopSummary.fromJson(Map<String, dynamic> json) => _$ShopSummaryFromJson(json);

@override@JsonKey(readValue: _readShopId) final  String id;
@override final  String name;
@override final  String? area;
@override final  String? phone;
@override@JsonKey()@MoneyConverter() final  Money receivable;

/// Create a copy of ShopSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShopSummaryCopyWith<_ShopSummary> get copyWith => __$ShopSummaryCopyWithImpl<_ShopSummary>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ShopSummaryToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShopSummary&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.area, area) || other.area == area)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.receivable, receivable) || other.receivable == receivable));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name,area,phone,receivable);
}

@override
String toString() {
    return 'ShopSummary(id: $id, name: $name, area: $area, phone: $phone, receivable: $receivable)';
}


}

/// @nodoc
abstract mixin class _$ShopSummaryCopyWith<$Res> implements $ShopSummaryCopyWith<$Res> {
  factory _$ShopSummaryCopyWith(_ShopSummary value, $Res Function(_ShopSummary) _then) = __$ShopSummaryCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(readValue: _readShopId) String id, String name, String? area, String? phone,@MoneyConverter() Money receivable
});




}
/// @nodoc
class __$ShopSummaryCopyWithImpl<$Res>
    implements _$ShopSummaryCopyWith<$Res> {
  __$ShopSummaryCopyWithImpl(this._self, this._then);

  final _ShopSummary _self;
  final $Res Function(_ShopSummary) _then;

/// Create a copy of ShopSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? area = freezed,Object? phone = freezed,Object? receivable = null,}) {
  return _then(_ShopSummary(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,area: freezed == area ? _self.area : area // ignore: cast_nullable_to_non_nullable
as String?,phone: freezed == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String?,receivable: null == receivable ? _self.receivable : receivable // ignore: cast_nullable_to_non_nullable
as Money,
  ));
}


}


/// @nodoc
mixin _$ShopDetail {

 String get id; String get companyId; String get name; String? get area; String? get phone; List<String> get phones; String? get phoneSource; String? get contactPerson; String? get email; String? get gstin; String? get address; List<String> get addressLines; String? get state; String? get pincode;@MoneyConverter() Money get openingBalanceAmount; String get openingBalanceType;@MoneyConverter() Money get receivable; DateTime? get syncedAt;
/// Create a copy of ShopDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShopDetailCopyWith<ShopDetail> get copyWith => _$ShopDetailCopyWithImpl<ShopDetail>(this as ShopDetail, _$identity);

  /// Serializes this ShopDetail to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ShopDetail;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShopDetail&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.companyId, _this.companyId) || other.companyId == _this.companyId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.area, _this.area) || other.area == _this.area)&&(identical(other.phone, _this.phone) || other.phone == _this.phone)&&const DeepCollectionEquality().equals(other.phones, _this.phones)&&(identical(other.phoneSource, _this.phoneSource) || other.phoneSource == _this.phoneSource)&&(identical(other.contactPerson, _this.contactPerson) || other.contactPerson == _this.contactPerson)&&(identical(other.email, _this.email) || other.email == _this.email)&&(identical(other.gstin, _this.gstin) || other.gstin == _this.gstin)&&(identical(other.address, _this.address) || other.address == _this.address)&&const DeepCollectionEquality().equals(other.addressLines, _this.addressLines)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.pincode, _this.pincode) || other.pincode == _this.pincode)&&(identical(other.openingBalanceAmount, _this.openingBalanceAmount) || other.openingBalanceAmount == _this.openingBalanceAmount)&&(identical(other.openingBalanceType, _this.openingBalanceType) || other.openingBalanceType == _this.openingBalanceType)&&(identical(other.receivable, _this.receivable) || other.receivable == _this.receivable)&&(identical(other.syncedAt, _this.syncedAt) || other.syncedAt == _this.syncedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ShopDetail;
  return Object.hash(runtimeType,_this.id,_this.companyId,_this.name,_this.area,_this.phone,const DeepCollectionEquality().hash(_this.phones),_this.phoneSource,_this.contactPerson,_this.email,_this.gstin,_this.address,const DeepCollectionEquality().hash(_this.addressLines),_this.state,_this.pincode,_this.openingBalanceAmount,_this.openingBalanceType,_this.receivable,_this.syncedAt);
}

@override
String toString() {
  final _this = this as ShopDetail;
  return 'ShopDetail(id: ${_this.id}, companyId: ${_this.companyId}, name: ${_this.name}, area: ${_this.area}, phone: ${_this.phone}, phones: ${_this.phones}, phoneSource: ${_this.phoneSource}, contactPerson: ${_this.contactPerson}, email: ${_this.email}, gstin: ${_this.gstin}, address: ${_this.address}, addressLines: ${_this.addressLines}, state: ${_this.state}, pincode: ${_this.pincode}, openingBalanceAmount: ${_this.openingBalanceAmount}, openingBalanceType: ${_this.openingBalanceType}, receivable: ${_this.receivable}, syncedAt: ${_this.syncedAt})';
}


}

/// @nodoc
abstract mixin class $ShopDetailCopyWith<$Res>  {
  factory $ShopDetailCopyWith(ShopDetail value, $Res Function(ShopDetail) _then) = _$ShopDetailCopyWithImpl;
@useResult
$Res call({
 String id, String companyId, String name, String? area, String? phone, List<String> phones, String? phoneSource, String? contactPerson, String? email, String? gstin, String? address, List<String> addressLines, String? state, String? pincode,@MoneyConverter() Money openingBalanceAmount, String openingBalanceType,@MoneyConverter() Money receivable, DateTime? syncedAt
});




}
/// @nodoc
class _$ShopDetailCopyWithImpl<$Res>
    implements $ShopDetailCopyWith<$Res> {
  _$ShopDetailCopyWithImpl(this._self, this._then);

  final ShopDetail _self;
  final $Res Function(ShopDetail) _then;

/// Create a copy of ShopDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? companyId = null,Object? name = null,Object? area = freezed,Object? phone = freezed,Object? phones = null,Object? phoneSource = freezed,Object? contactPerson = freezed,Object? email = freezed,Object? gstin = freezed,Object? address = freezed,Object? addressLines = null,Object? state = freezed,Object? pincode = freezed,Object? openingBalanceAmount = null,Object? openingBalanceType = null,Object? receivable = null,Object? syncedAt = freezed,}) {
  return _then(ShopDetail(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,companyId: null == companyId ? _self.companyId : companyId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,area: freezed == area ? _self.area : area // ignore: cast_nullable_to_non_nullable
as String?,phone: freezed == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String?,phones: null == phones ? _self.phones : phones // ignore: cast_nullable_to_non_nullable
as List<String>,phoneSource: freezed == phoneSource ? _self.phoneSource : phoneSource // ignore: cast_nullable_to_non_nullable
as String?,contactPerson: freezed == contactPerson ? _self.contactPerson : contactPerson // ignore: cast_nullable_to_non_nullable
as String?,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,gstin: freezed == gstin ? _self.gstin : gstin // ignore: cast_nullable_to_non_nullable
as String?,address: freezed == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String?,addressLines: null == addressLines ? _self.addressLines : addressLines // ignore: cast_nullable_to_non_nullable
as List<String>,state: freezed == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String?,pincode: freezed == pincode ? _self.pincode : pincode // ignore: cast_nullable_to_non_nullable
as String?,openingBalanceAmount: null == openingBalanceAmount ? _self.openingBalanceAmount : openingBalanceAmount // ignore: cast_nullable_to_non_nullable
as Money,openingBalanceType: null == openingBalanceType ? _self.openingBalanceType : openingBalanceType // ignore: cast_nullable_to_non_nullable
as String,receivable: null == receivable ? _self.receivable : receivable // ignore: cast_nullable_to_non_nullable
as Money,syncedAt: freezed == syncedAt ? _self.syncedAt : syncedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [ShopDetail].
extension ShopDetailPatterns on ShopDetail {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShopDetail value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShopDetail() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShopDetail value)  $default,){
final _that = this;
switch (_that) {
case _ShopDetail():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShopDetail value)?  $default,){
final _that = this;
switch (_that) {
case _ShopDetail() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String companyId,  String name,  String? area,  String? phone,  List<String> phones,  String? phoneSource,  String? contactPerson,  String? email,  String? gstin,  String? address,  List<String> addressLines,  String? state,  String? pincode, @MoneyConverter()  Money openingBalanceAmount,  String openingBalanceType, @MoneyConverter()  Money receivable,  DateTime? syncedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShopDetail() when $default != null:
return $default(_that.id,_that.companyId,_that.name,_that.area,_that.phone,_that.phones,_that.phoneSource,_that.contactPerson,_that.email,_that.gstin,_that.address,_that.addressLines,_that.state,_that.pincode,_that.openingBalanceAmount,_that.openingBalanceType,_that.receivable,_that.syncedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String companyId,  String name,  String? area,  String? phone,  List<String> phones,  String? phoneSource,  String? contactPerson,  String? email,  String? gstin,  String? address,  List<String> addressLines,  String? state,  String? pincode, @MoneyConverter()  Money openingBalanceAmount,  String openingBalanceType, @MoneyConverter()  Money receivable,  DateTime? syncedAt)  $default,) {final _that = this;
switch (_that) {
case _ShopDetail():
return $default(_that.id,_that.companyId,_that.name,_that.area,_that.phone,_that.phones,_that.phoneSource,_that.contactPerson,_that.email,_that.gstin,_that.address,_that.addressLines,_that.state,_that.pincode,_that.openingBalanceAmount,_that.openingBalanceType,_that.receivable,_that.syncedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String companyId,  String name,  String? area,  String? phone,  List<String> phones,  String? phoneSource,  String? contactPerson,  String? email,  String? gstin,  String? address,  List<String> addressLines,  String? state,  String? pincode, @MoneyConverter()  Money openingBalanceAmount,  String openingBalanceType, @MoneyConverter()  Money receivable,  DateTime? syncedAt)?  $default,) {final _that = this;
switch (_that) {
case _ShopDetail() when $default != null:
return $default(_that.id,_that.companyId,_that.name,_that.area,_that.phone,_that.phones,_that.phoneSource,_that.contactPerson,_that.email,_that.gstin,_that.address,_that.addressLines,_that.state,_that.pincode,_that.openingBalanceAmount,_that.openingBalanceType,_that.receivable,_that.syncedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ShopDetail extends ShopDetail {
  const _ShopDetail({required this.id, required this.companyId, required this.name, this.area, this.phone,  List<String> phones = const <String>[], this.phoneSource, this.contactPerson, this.email, this.gstin, this.address,  List<String> addressLines = const <String>[], this.state, this.pincode, @MoneyConverter() this.openingBalanceAmount = Money.zero, this.openingBalanceType = '', @MoneyConverter() this.receivable = Money.zero, this.syncedAt}): _phones = phones,_addressLines = addressLines,super._();
  factory _ShopDetail.fromJson(Map<String, dynamic> json) => _$ShopDetailFromJson(json);

@override final  String id;
@override final  String companyId;
@override final  String name;
@override final  String? area;
@override final  String? phone;
 final  List<String> _phones;
@override@JsonKey() List<String> get phones {
  if (_phones is EqualUnmodifiableListView) return _phones;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_phones);
}

@override final  String? phoneSource;
@override final  String? contactPerson;
@override final  String? email;
@override final  String? gstin;
@override final  String? address;
 final  List<String> _addressLines;
@override@JsonKey() List<String> get addressLines {
  if (_addressLines is EqualUnmodifiableListView) return _addressLines;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_addressLines);
}

@override final  String? state;
@override final  String? pincode;
@override@JsonKey()@MoneyConverter() final  Money openingBalanceAmount;
@override@JsonKey() final  String openingBalanceType;
@override@JsonKey()@MoneyConverter() final  Money receivable;
@override final  DateTime? syncedAt;

/// Create a copy of ShopDetail
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShopDetailCopyWith<_ShopDetail> get copyWith => __$ShopDetailCopyWithImpl<_ShopDetail>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ShopDetailToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShopDetail&&(identical(other.id, id) || other.id == id)&&(identical(other.companyId, companyId) || other.companyId == companyId)&&(identical(other.name, name) || other.name == name)&&(identical(other.area, area) || other.area == area)&&(identical(other.phone, phone) || other.phone == phone)&&const DeepCollectionEquality().equals(other.phones, _phones)&&(identical(other.phoneSource, phoneSource) || other.phoneSource == phoneSource)&&(identical(other.contactPerson, contactPerson) || other.contactPerson == contactPerson)&&(identical(other.email, email) || other.email == email)&&(identical(other.gstin, gstin) || other.gstin == gstin)&&(identical(other.address, address) || other.address == address)&&const DeepCollectionEquality().equals(other.addressLines, _addressLines)&&(identical(other.state, state) || other.state == state)&&(identical(other.pincode, pincode) || other.pincode == pincode)&&(identical(other.openingBalanceAmount, openingBalanceAmount) || other.openingBalanceAmount == openingBalanceAmount)&&(identical(other.openingBalanceType, openingBalanceType) || other.openingBalanceType == openingBalanceType)&&(identical(other.receivable, receivable) || other.receivable == receivable)&&(identical(other.syncedAt, syncedAt) || other.syncedAt == syncedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,companyId,name,area,phone,const DeepCollectionEquality().hash(_phones),phoneSource,contactPerson,email,gstin,address,const DeepCollectionEquality().hash(_addressLines),state,pincode,openingBalanceAmount,openingBalanceType,receivable,syncedAt);
}

@override
String toString() {
    return 'ShopDetail(id: $id, companyId: $companyId, name: $name, area: $area, phone: $phone, phones: $phones, phoneSource: $phoneSource, contactPerson: $contactPerson, email: $email, gstin: $gstin, address: $address, addressLines: $addressLines, state: $state, pincode: $pincode, openingBalanceAmount: $openingBalanceAmount, openingBalanceType: $openingBalanceType, receivable: $receivable, syncedAt: $syncedAt)';
}


}

/// @nodoc
abstract mixin class _$ShopDetailCopyWith<$Res> implements $ShopDetailCopyWith<$Res> {
  factory _$ShopDetailCopyWith(_ShopDetail value, $Res Function(_ShopDetail) _then) = __$ShopDetailCopyWithImpl;
@override @useResult
$Res call({
 String id, String companyId, String name, String? area, String? phone, List<String> phones, String? phoneSource, String? contactPerson, String? email, String? gstin, String? address, List<String> addressLines, String? state, String? pincode,@MoneyConverter() Money openingBalanceAmount, String openingBalanceType,@MoneyConverter() Money receivable, DateTime? syncedAt
});




}
/// @nodoc
class __$ShopDetailCopyWithImpl<$Res>
    implements _$ShopDetailCopyWith<$Res> {
  __$ShopDetailCopyWithImpl(this._self, this._then);

  final _ShopDetail _self;
  final $Res Function(_ShopDetail) _then;

/// Create a copy of ShopDetail
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? companyId = null,Object? name = null,Object? area = freezed,Object? phone = freezed,Object? phones = null,Object? phoneSource = freezed,Object? contactPerson = freezed,Object? email = freezed,Object? gstin = freezed,Object? address = freezed,Object? addressLines = null,Object? state = freezed,Object? pincode = freezed,Object? openingBalanceAmount = null,Object? openingBalanceType = null,Object? receivable = null,Object? syncedAt = freezed,}) {
  return _then(_ShopDetail(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,companyId: null == companyId ? _self.companyId : companyId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,area: freezed == area ? _self.area : area // ignore: cast_nullable_to_non_nullable
as String?,phone: freezed == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String?,phones: null == phones ? _self._phones : phones // ignore: cast_nullable_to_non_nullable
as List<String>,phoneSource: freezed == phoneSource ? _self.phoneSource : phoneSource // ignore: cast_nullable_to_non_nullable
as String?,contactPerson: freezed == contactPerson ? _self.contactPerson : contactPerson // ignore: cast_nullable_to_non_nullable
as String?,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,gstin: freezed == gstin ? _self.gstin : gstin // ignore: cast_nullable_to_non_nullable
as String?,address: freezed == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String?,addressLines: null == addressLines ? _self._addressLines : addressLines // ignore: cast_nullable_to_non_nullable
as List<String>,state: freezed == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String?,pincode: freezed == pincode ? _self.pincode : pincode // ignore: cast_nullable_to_non_nullable
as String?,openingBalanceAmount: null == openingBalanceAmount ? _self.openingBalanceAmount : openingBalanceAmount // ignore: cast_nullable_to_non_nullable
as Money,openingBalanceType: null == openingBalanceType ? _self.openingBalanceType : openingBalanceType // ignore: cast_nullable_to_non_nullable
as String,receivable: null == receivable ? _self.receivable : receivable // ignore: cast_nullable_to_non_nullable
as Money,syncedAt: freezed == syncedAt ? _self.syncedAt : syncedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc
mixin _$ShopFilter {

 String get query; BalanceFilter get balance; Set<String> get areas; ShopSort get sort;
/// Create a copy of ShopFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShopFilterCopyWith<ShopFilter> get copyWith => _$ShopFilterCopyWithImpl<ShopFilter>(this as ShopFilter, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ShopFilter;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShopFilter&&(identical(other.query, _this.query) || other.query == _this.query)&&(identical(other.balance, _this.balance) || other.balance == _this.balance)&&const DeepCollectionEquality().equals(other.areas, _this.areas)&&(identical(other.sort, _this.sort) || other.sort == _this.sort));
}


@override
int get hashCode {
  final _this = this as ShopFilter;
  return Object.hash(runtimeType,_this.query,_this.balance,const DeepCollectionEquality().hash(_this.areas),_this.sort);
}

@override
String toString() {
  final _this = this as ShopFilter;
  return 'ShopFilter(query: ${_this.query}, balance: ${_this.balance}, areas: ${_this.areas}, sort: ${_this.sort})';
}


}

/// @nodoc
abstract mixin class $ShopFilterCopyWith<$Res>  {
  factory $ShopFilterCopyWith(ShopFilter value, $Res Function(ShopFilter) _then) = _$ShopFilterCopyWithImpl;
@useResult
$Res call({
 String query, BalanceFilter balance, Set<String> areas, ShopSort sort
});




}
/// @nodoc
class _$ShopFilterCopyWithImpl<$Res>
    implements $ShopFilterCopyWith<$Res> {
  _$ShopFilterCopyWithImpl(this._self, this._then);

  final ShopFilter _self;
  final $Res Function(ShopFilter) _then;

/// Create a copy of ShopFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? query = null,Object? balance = null,Object? areas = null,Object? sort = null,}) {
  return _then(ShopFilter(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,balance: null == balance ? _self.balance : balance // ignore: cast_nullable_to_non_nullable
as BalanceFilter,areas: null == areas ? _self.areas : areas // ignore: cast_nullable_to_non_nullable
as Set<String>,sort: null == sort ? _self.sort : sort // ignore: cast_nullable_to_non_nullable
as ShopSort,
  ));
}

}


/// Adds pattern-matching-related methods to [ShopFilter].
extension ShopFilterPatterns on ShopFilter {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShopFilter value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShopFilter() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShopFilter value)  $default,){
final _that = this;
switch (_that) {
case _ShopFilter():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShopFilter value)?  $default,){
final _that = this;
switch (_that) {
case _ShopFilter() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String query,  BalanceFilter balance,  Set<String> areas,  ShopSort sort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShopFilter() when $default != null:
return $default(_that.query,_that.balance,_that.areas,_that.sort);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String query,  BalanceFilter balance,  Set<String> areas,  ShopSort sort)  $default,) {final _that = this;
switch (_that) {
case _ShopFilter():
return $default(_that.query,_that.balance,_that.areas,_that.sort);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String query,  BalanceFilter balance,  Set<String> areas,  ShopSort sort)?  $default,) {final _that = this;
switch (_that) {
case _ShopFilter() when $default != null:
return $default(_that.query,_that.balance,_that.areas,_that.sort);case _:
  return null;

}
}

}

/// @nodoc


class _ShopFilter implements ShopFilter {
  const _ShopFilter({this.query = '', this.balance = BalanceFilter.all,  Set<String> areas = const <String>{}, this.sort = ShopSort.balanceDesc}): _areas = areas;
  

@override@JsonKey() final  String query;
@override@JsonKey() final  BalanceFilter balance;
 final  Set<String> _areas;
@override@JsonKey() Set<String> get areas {
  if (_areas is EqualUnmodifiableSetView) return _areas;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_areas);
}

@override@JsonKey() final  ShopSort sort;

/// Create a copy of ShopFilter
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShopFilterCopyWith<_ShopFilter> get copyWith => __$ShopFilterCopyWithImpl<_ShopFilter>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShopFilter&&(identical(other.query, query) || other.query == query)&&(identical(other.balance, balance) || other.balance == balance)&&const DeepCollectionEquality().equals(other.areas, _areas)&&(identical(other.sort, sort) || other.sort == sort));
}


@override
int get hashCode {
    return Object.hash(runtimeType,query,balance,const DeepCollectionEquality().hash(_areas),sort);
}

@override
String toString() {
    return 'ShopFilter(query: $query, balance: $balance, areas: $areas, sort: $sort)';
}


}

/// @nodoc
abstract mixin class _$ShopFilterCopyWith<$Res> implements $ShopFilterCopyWith<$Res> {
  factory _$ShopFilterCopyWith(_ShopFilter value, $Res Function(_ShopFilter) _then) = __$ShopFilterCopyWithImpl;
@override @useResult
$Res call({
 String query, BalanceFilter balance, Set<String> areas, ShopSort sort
});




}
/// @nodoc
class __$ShopFilterCopyWithImpl<$Res>
    implements _$ShopFilterCopyWith<$Res> {
  __$ShopFilterCopyWithImpl(this._self, this._then);

  final _ShopFilter _self;
  final $Res Function(_ShopFilter) _then;

/// Create a copy of ShopFilter
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? query = null,Object? balance = null,Object? areas = null,Object? sort = null,}) {
  return _then(_ShopFilter(
query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,balance: null == balance ? _self.balance : balance // ignore: cast_nullable_to_non_nullable
as BalanceFilter,areas: null == areas ? _self._areas : areas // ignore: cast_nullable_to_non_nullable
as Set<String>,sort: null == sort ? _self.sort : sort // ignore: cast_nullable_to_non_nullable
as ShopSort,
  ));
}


}

// dart format on
