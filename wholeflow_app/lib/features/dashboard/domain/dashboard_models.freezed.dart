// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'dashboard_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CompanySummary {

 String get companyId; String get companyName; int get shops; int get shopsWithDues;@MoneyConverter() Money get totalOutstanding;@MoneyConverter() Money get totalCredit;
/// Create a copy of CompanySummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CompanySummaryCopyWith<CompanySummary> get copyWith => _$CompanySummaryCopyWithImpl<CompanySummary>(this as CompanySummary, _$identity);

  /// Serializes this CompanySummary to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as CompanySummary;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CompanySummary&&(identical(other.companyId, _this.companyId) || other.companyId == _this.companyId)&&(identical(other.companyName, _this.companyName) || other.companyName == _this.companyName)&&(identical(other.shops, _this.shops) || other.shops == _this.shops)&&(identical(other.shopsWithDues, _this.shopsWithDues) || other.shopsWithDues == _this.shopsWithDues)&&(identical(other.totalOutstanding, _this.totalOutstanding) || other.totalOutstanding == _this.totalOutstanding)&&(identical(other.totalCredit, _this.totalCredit) || other.totalCredit == _this.totalCredit));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as CompanySummary;
  return Object.hash(runtimeType,_this.companyId,_this.companyName,_this.shops,_this.shopsWithDues,_this.totalOutstanding,_this.totalCredit);
}

@override
String toString() {
  final _this = this as CompanySummary;
  return 'CompanySummary(companyId: ${_this.companyId}, companyName: ${_this.companyName}, shops: ${_this.shops}, shopsWithDues: ${_this.shopsWithDues}, totalOutstanding: ${_this.totalOutstanding}, totalCredit: ${_this.totalCredit})';
}


}

/// @nodoc
abstract mixin class $CompanySummaryCopyWith<$Res>  {
  factory $CompanySummaryCopyWith(CompanySummary value, $Res Function(CompanySummary) _then) = _$CompanySummaryCopyWithImpl;
@useResult
$Res call({
 String companyId, String companyName, int shops, int shopsWithDues,@MoneyConverter() Money totalOutstanding,@MoneyConverter() Money totalCredit
});




}
/// @nodoc
class _$CompanySummaryCopyWithImpl<$Res>
    implements $CompanySummaryCopyWith<$Res> {
  _$CompanySummaryCopyWithImpl(this._self, this._then);

  final CompanySummary _self;
  final $Res Function(CompanySummary) _then;

/// Create a copy of CompanySummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? companyId = null,Object? companyName = null,Object? shops = null,Object? shopsWithDues = null,Object? totalOutstanding = null,Object? totalCredit = null,}) {
  return _then(CompanySummary(
companyId: null == companyId ? _self.companyId : companyId // ignore: cast_nullable_to_non_nullable
as String,companyName: null == companyName ? _self.companyName : companyName // ignore: cast_nullable_to_non_nullable
as String,shops: null == shops ? _self.shops : shops // ignore: cast_nullable_to_non_nullable
as int,shopsWithDues: null == shopsWithDues ? _self.shopsWithDues : shopsWithDues // ignore: cast_nullable_to_non_nullable
as int,totalOutstanding: null == totalOutstanding ? _self.totalOutstanding : totalOutstanding // ignore: cast_nullable_to_non_nullable
as Money,totalCredit: null == totalCredit ? _self.totalCredit : totalCredit // ignore: cast_nullable_to_non_nullable
as Money,
  ));
}

}


/// Adds pattern-matching-related methods to [CompanySummary].
extension CompanySummaryPatterns on CompanySummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CompanySummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CompanySummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CompanySummary value)  $default,){
final _that = this;
switch (_that) {
case _CompanySummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CompanySummary value)?  $default,){
final _that = this;
switch (_that) {
case _CompanySummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String companyId,  String companyName,  int shops,  int shopsWithDues, @MoneyConverter()  Money totalOutstanding, @MoneyConverter()  Money totalCredit)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CompanySummary() when $default != null:
return $default(_that.companyId,_that.companyName,_that.shops,_that.shopsWithDues,_that.totalOutstanding,_that.totalCredit);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String companyId,  String companyName,  int shops,  int shopsWithDues, @MoneyConverter()  Money totalOutstanding, @MoneyConverter()  Money totalCredit)  $default,) {final _that = this;
switch (_that) {
case _CompanySummary():
return $default(_that.companyId,_that.companyName,_that.shops,_that.shopsWithDues,_that.totalOutstanding,_that.totalCredit);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String companyId,  String companyName,  int shops,  int shopsWithDues, @MoneyConverter()  Money totalOutstanding, @MoneyConverter()  Money totalCredit)?  $default,) {final _that = this;
switch (_that) {
case _CompanySummary() when $default != null:
return $default(_that.companyId,_that.companyName,_that.shops,_that.shopsWithDues,_that.totalOutstanding,_that.totalCredit);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CompanySummary implements CompanySummary {
  const _CompanySummary({required this.companyId, required this.companyName, this.shops = 0, this.shopsWithDues = 0, @MoneyConverter() this.totalOutstanding = Money.zero, @MoneyConverter() this.totalCredit = Money.zero});
  factory _CompanySummary.fromJson(Map<String, dynamic> json) => _$CompanySummaryFromJson(json);

@override final  String companyId;
@override final  String companyName;
@override@JsonKey() final  int shops;
@override@JsonKey() final  int shopsWithDues;
@override@JsonKey()@MoneyConverter() final  Money totalOutstanding;
@override@JsonKey()@MoneyConverter() final  Money totalCredit;

/// Create a copy of CompanySummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CompanySummaryCopyWith<_CompanySummary> get copyWith => __$CompanySummaryCopyWithImpl<_CompanySummary>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CompanySummaryToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CompanySummary&&(identical(other.companyId, companyId) || other.companyId == companyId)&&(identical(other.companyName, companyName) || other.companyName == companyName)&&(identical(other.shops, shops) || other.shops == shops)&&(identical(other.shopsWithDues, shopsWithDues) || other.shopsWithDues == shopsWithDues)&&(identical(other.totalOutstanding, totalOutstanding) || other.totalOutstanding == totalOutstanding)&&(identical(other.totalCredit, totalCredit) || other.totalCredit == totalCredit));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,companyId,companyName,shops,shopsWithDues,totalOutstanding,totalCredit);
}

@override
String toString() {
    return 'CompanySummary(companyId: $companyId, companyName: $companyName, shops: $shops, shopsWithDues: $shopsWithDues, totalOutstanding: $totalOutstanding, totalCredit: $totalCredit)';
}


}

/// @nodoc
abstract mixin class _$CompanySummaryCopyWith<$Res> implements $CompanySummaryCopyWith<$Res> {
  factory _$CompanySummaryCopyWith(_CompanySummary value, $Res Function(_CompanySummary) _then) = __$CompanySummaryCopyWithImpl;
@override @useResult
$Res call({
 String companyId, String companyName, int shops, int shopsWithDues,@MoneyConverter() Money totalOutstanding,@MoneyConverter() Money totalCredit
});




}
/// @nodoc
class __$CompanySummaryCopyWithImpl<$Res>
    implements _$CompanySummaryCopyWith<$Res> {
  __$CompanySummaryCopyWithImpl(this._self, this._then);

  final _CompanySummary _self;
  final $Res Function(_CompanySummary) _then;

/// Create a copy of CompanySummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? companyId = null,Object? companyName = null,Object? shops = null,Object? shopsWithDues = null,Object? totalOutstanding = null,Object? totalCredit = null,}) {
  return _then(_CompanySummary(
companyId: null == companyId ? _self.companyId : companyId // ignore: cast_nullable_to_non_nullable
as String,companyName: null == companyName ? _self.companyName : companyName // ignore: cast_nullable_to_non_nullable
as String,shops: null == shops ? _self.shops : shops // ignore: cast_nullable_to_non_nullable
as int,shopsWithDues: null == shopsWithDues ? _self.shopsWithDues : shopsWithDues // ignore: cast_nullable_to_non_nullable
as int,totalOutstanding: null == totalOutstanding ? _self.totalOutstanding : totalOutstanding // ignore: cast_nullable_to_non_nullable
as Money,totalCredit: null == totalCredit ? _self.totalCredit : totalCredit // ignore: cast_nullable_to_non_nullable
as Money,
  ));
}


}


/// @nodoc
mixin _$SyncState {

 DateTime? get lastSuccessfulSyncAt; DateTime? get lastAttemptAt; String get status; String? get errorCode; String? get errorMessage;
/// Create a copy of SyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncStateCopyWith<SyncState> get copyWith => _$SyncStateCopyWithImpl<SyncState>(this as SyncState, _$identity);

  /// Serializes this SyncState to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SyncState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncState&&(identical(other.lastSuccessfulSyncAt, _this.lastSuccessfulSyncAt) || other.lastSuccessfulSyncAt == _this.lastSuccessfulSyncAt)&&(identical(other.lastAttemptAt, _this.lastAttemptAt) || other.lastAttemptAt == _this.lastAttemptAt)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.errorCode, _this.errorCode) || other.errorCode == _this.errorCode)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SyncState;
  return Object.hash(runtimeType,_this.lastSuccessfulSyncAt,_this.lastAttemptAt,_this.status,_this.errorCode,_this.errorMessage);
}

@override
String toString() {
  final _this = this as SyncState;
  return 'SyncState(lastSuccessfulSyncAt: ${_this.lastSuccessfulSyncAt}, lastAttemptAt: ${_this.lastAttemptAt}, status: ${_this.status}, errorCode: ${_this.errorCode}, errorMessage: ${_this.errorMessage})';
}


}

/// @nodoc
abstract mixin class $SyncStateCopyWith<$Res>  {
  factory $SyncStateCopyWith(SyncState value, $Res Function(SyncState) _then) = _$SyncStateCopyWithImpl;
@useResult
$Res call({
 DateTime? lastSuccessfulSyncAt, DateTime? lastAttemptAt, String status, String? errorCode, String? errorMessage
});




}
/// @nodoc
class _$SyncStateCopyWithImpl<$Res>
    implements $SyncStateCopyWith<$Res> {
  _$SyncStateCopyWithImpl(this._self, this._then);

  final SyncState _self;
  final $Res Function(SyncState) _then;

/// Create a copy of SyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? lastSuccessfulSyncAt = freezed,Object? lastAttemptAt = freezed,Object? status = null,Object? errorCode = freezed,Object? errorMessage = freezed,}) {
  return _then(SyncState(
lastSuccessfulSyncAt: freezed == lastSuccessfulSyncAt ? _self.lastSuccessfulSyncAt : lastSuccessfulSyncAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastAttemptAt: freezed == lastAttemptAt ? _self.lastAttemptAt : lastAttemptAt // ignore: cast_nullable_to_non_nullable
as DateTime?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [SyncState].
extension SyncStatePatterns on SyncState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SyncState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SyncState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SyncState value)  $default,){
final _that = this;
switch (_that) {
case _SyncState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SyncState value)?  $default,){
final _that = this;
switch (_that) {
case _SyncState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DateTime? lastSuccessfulSyncAt,  DateTime? lastAttemptAt,  String status,  String? errorCode,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SyncState() when $default != null:
return $default(_that.lastSuccessfulSyncAt,_that.lastAttemptAt,_that.status,_that.errorCode,_that.errorMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DateTime? lastSuccessfulSyncAt,  DateTime? lastAttemptAt,  String status,  String? errorCode,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _SyncState():
return $default(_that.lastSuccessfulSyncAt,_that.lastAttemptAt,_that.status,_that.errorCode,_that.errorMessage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DateTime? lastSuccessfulSyncAt,  DateTime? lastAttemptAt,  String status,  String? errorCode,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _SyncState() when $default != null:
return $default(_that.lastSuccessfulSyncAt,_that.lastAttemptAt,_that.status,_that.errorCode,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SyncState implements SyncState {
  const _SyncState({this.lastSuccessfulSyncAt, this.lastAttemptAt, this.status = 'ok', this.errorCode, this.errorMessage});
  factory _SyncState.fromJson(Map<String, dynamic> json) => _$SyncStateFromJson(json);

@override final  DateTime? lastSuccessfulSyncAt;
@override final  DateTime? lastAttemptAt;
@override@JsonKey() final  String status;
@override final  String? errorCode;
@override final  String? errorMessage;

/// Create a copy of SyncState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SyncStateCopyWith<_SyncState> get copyWith => __$SyncStateCopyWithImpl<_SyncState>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SyncStateToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SyncState&&(identical(other.lastSuccessfulSyncAt, lastSuccessfulSyncAt) || other.lastSuccessfulSyncAt == lastSuccessfulSyncAt)&&(identical(other.lastAttemptAt, lastAttemptAt) || other.lastAttemptAt == lastAttemptAt)&&(identical(other.status, status) || other.status == status)&&(identical(other.errorCode, errorCode) || other.errorCode == errorCode)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,lastSuccessfulSyncAt,lastAttemptAt,status,errorCode,errorMessage);
}

@override
String toString() {
    return 'SyncState(lastSuccessfulSyncAt: $lastSuccessfulSyncAt, lastAttemptAt: $lastAttemptAt, status: $status, errorCode: $errorCode, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$SyncStateCopyWith<$Res> implements $SyncStateCopyWith<$Res> {
  factory _$SyncStateCopyWith(_SyncState value, $Res Function(_SyncState) _then) = __$SyncStateCopyWithImpl;
@override @useResult
$Res call({
 DateTime? lastSuccessfulSyncAt, DateTime? lastAttemptAt, String status, String? errorCode, String? errorMessage
});




}
/// @nodoc
class __$SyncStateCopyWithImpl<$Res>
    implements _$SyncStateCopyWith<$Res> {
  __$SyncStateCopyWithImpl(this._self, this._then);

  final _SyncState _self;
  final $Res Function(_SyncState) _then;

/// Create a copy of SyncState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? lastSuccessfulSyncAt = freezed,Object? lastAttemptAt = freezed,Object? status = null,Object? errorCode = freezed,Object? errorMessage = freezed,}) {
  return _then(_SyncState(
lastSuccessfulSyncAt: freezed == lastSuccessfulSyncAt ? _self.lastSuccessfulSyncAt : lastSuccessfulSyncAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastAttemptAt: freezed == lastAttemptAt ? _self.lastAttemptAt : lastAttemptAt // ignore: cast_nullable_to_non_nullable
as DateTime?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
