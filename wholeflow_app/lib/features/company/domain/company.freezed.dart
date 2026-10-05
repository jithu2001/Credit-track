// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'company.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Company {

 String get id; String get companyName; String get syncStatus; DateTime? get lastSyncAt;
/// Create a copy of Company
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CompanyCopyWith<Company> get copyWith => _$CompanyCopyWithImpl<Company>(this as Company, _$identity);

  /// Serializes this Company to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Company;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Company&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.companyName, _this.companyName) || other.companyName == _this.companyName)&&(identical(other.syncStatus, _this.syncStatus) || other.syncStatus == _this.syncStatus)&&(identical(other.lastSyncAt, _this.lastSyncAt) || other.lastSyncAt == _this.lastSyncAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Company;
  return Object.hash(runtimeType,_this.id,_this.companyName,_this.syncStatus,_this.lastSyncAt);
}

@override
String toString() {
  final _this = this as Company;
  return 'Company(id: ${_this.id}, companyName: ${_this.companyName}, syncStatus: ${_this.syncStatus}, lastSyncAt: ${_this.lastSyncAt})';
}


}

/// @nodoc
abstract mixin class $CompanyCopyWith<$Res>  {
  factory $CompanyCopyWith(Company value, $Res Function(Company) _then) = _$CompanyCopyWithImpl;
@useResult
$Res call({
 String id, String companyName, String syncStatus, DateTime? lastSyncAt
});




}
/// @nodoc
class _$CompanyCopyWithImpl<$Res>
    implements $CompanyCopyWith<$Res> {
  _$CompanyCopyWithImpl(this._self, this._then);

  final Company _self;
  final $Res Function(Company) _then;

/// Create a copy of Company
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? companyName = null,Object? syncStatus = null,Object? lastSyncAt = freezed,}) {
  return _then(Company(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,companyName: null == companyName ? _self.companyName : companyName // ignore: cast_nullable_to_non_nullable
as String,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as String,lastSyncAt: freezed == lastSyncAt ? _self.lastSyncAt : lastSyncAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Company].
extension CompanyPatterns on Company {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Company value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Company() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Company value)  $default,){
final _that = this;
switch (_that) {
case _Company():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Company value)?  $default,){
final _that = this;
switch (_that) {
case _Company() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String companyName,  String syncStatus,  DateTime? lastSyncAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Company() when $default != null:
return $default(_that.id,_that.companyName,_that.syncStatus,_that.lastSyncAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String companyName,  String syncStatus,  DateTime? lastSyncAt)  $default,) {final _that = this;
switch (_that) {
case _Company():
return $default(_that.id,_that.companyName,_that.syncStatus,_that.lastSyncAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String companyName,  String syncStatus,  DateTime? lastSyncAt)?  $default,) {final _that = this;
switch (_that) {
case _Company() when $default != null:
return $default(_that.id,_that.companyName,_that.syncStatus,_that.lastSyncAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Company implements Company {
  const _Company({required this.id, required this.companyName, this.syncStatus = 'PENDING', this.lastSyncAt});
  factory _Company.fromJson(Map<String, dynamic> json) => _$CompanyFromJson(json);

@override final  String id;
@override final  String companyName;
@override@JsonKey() final  String syncStatus;
@override final  DateTime? lastSyncAt;

/// Create a copy of Company
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CompanyCopyWith<_Company> get copyWith => __$CompanyCopyWithImpl<_Company>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CompanyToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Company&&(identical(other.id, id) || other.id == id)&&(identical(other.companyName, companyName) || other.companyName == companyName)&&(identical(other.syncStatus, syncStatus) || other.syncStatus == syncStatus)&&(identical(other.lastSyncAt, lastSyncAt) || other.lastSyncAt == lastSyncAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,companyName,syncStatus,lastSyncAt);
}

@override
String toString() {
    return 'Company(id: $id, companyName: $companyName, syncStatus: $syncStatus, lastSyncAt: $lastSyncAt)';
}


}

/// @nodoc
abstract mixin class _$CompanyCopyWith<$Res> implements $CompanyCopyWith<$Res> {
  factory _$CompanyCopyWith(_Company value, $Res Function(_Company) _then) = __$CompanyCopyWithImpl;
@override @useResult
$Res call({
 String id, String companyName, String syncStatus, DateTime? lastSyncAt
});




}
/// @nodoc
class __$CompanyCopyWithImpl<$Res>
    implements _$CompanyCopyWith<$Res> {
  __$CompanyCopyWithImpl(this._self, this._then);

  final _Company _self;
  final $Res Function(_Company) _then;

/// Create a copy of Company
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? companyName = null,Object? syncStatus = null,Object? lastSyncAt = freezed,}) {
  return _then(_Company(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,companyName: null == companyName ? _self.companyName : companyName // ignore: cast_nullable_to_non_nullable
as String,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as String,lastSyncAt: freezed == lastSyncAt ? _self.lastSyncAt : lastSyncAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}


/// @nodoc
mixin _$CompanyAccess {

 String get userId; String get companyId; bool get fullCompany;@JsonKey(includeFromJson: false, includeToJson: false) List<String> get siteIds; bool get canViewTransactions;
/// Create a copy of CompanyAccess
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CompanyAccessCopyWith<CompanyAccess> get copyWith => _$CompanyAccessCopyWithImpl<CompanyAccess>(this as CompanyAccess, _$identity);

  /// Serializes this CompanyAccess to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as CompanyAccess;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CompanyAccess&&(identical(other.userId, _this.userId) || other.userId == _this.userId)&&(identical(other.companyId, _this.companyId) || other.companyId == _this.companyId)&&(identical(other.fullCompany, _this.fullCompany) || other.fullCompany == _this.fullCompany)&&const DeepCollectionEquality().equals(other.siteIds, _this.siteIds)&&(identical(other.canViewTransactions, _this.canViewTransactions) || other.canViewTransactions == _this.canViewTransactions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as CompanyAccess;
  return Object.hash(runtimeType,_this.userId,_this.companyId,_this.fullCompany,const DeepCollectionEquality().hash(_this.siteIds),_this.canViewTransactions);
}

@override
String toString() {
  final _this = this as CompanyAccess;
  return 'CompanyAccess(userId: ${_this.userId}, companyId: ${_this.companyId}, fullCompany: ${_this.fullCompany}, siteIds: ${_this.siteIds}, canViewTransactions: ${_this.canViewTransactions})';
}


}

/// @nodoc
abstract mixin class $CompanyAccessCopyWith<$Res>  {
  factory $CompanyAccessCopyWith(CompanyAccess value, $Res Function(CompanyAccess) _then) = _$CompanyAccessCopyWithImpl;
@useResult
$Res call({
 String userId, String companyId, bool fullCompany,@JsonKey(includeFromJson: false, includeToJson: false) List<String> siteIds, bool canViewTransactions
});




}
/// @nodoc
class _$CompanyAccessCopyWithImpl<$Res>
    implements $CompanyAccessCopyWith<$Res> {
  _$CompanyAccessCopyWithImpl(this._self, this._then);

  final CompanyAccess _self;
  final $Res Function(CompanyAccess) _then;

/// Create a copy of CompanyAccess
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? userId = null,Object? companyId = null,Object? fullCompany = null,Object? siteIds = null,Object? canViewTransactions = null,}) {
  return _then(CompanyAccess(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,companyId: null == companyId ? _self.companyId : companyId // ignore: cast_nullable_to_non_nullable
as String,fullCompany: null == fullCompany ? _self.fullCompany : fullCompany // ignore: cast_nullable_to_non_nullable
as bool,siteIds: null == siteIds ? _self.siteIds : siteIds // ignore: cast_nullable_to_non_nullable
as List<String>,canViewTransactions: null == canViewTransactions ? _self.canViewTransactions : canViewTransactions // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [CompanyAccess].
extension CompanyAccessPatterns on CompanyAccess {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CompanyAccess value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CompanyAccess() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CompanyAccess value)  $default,){
final _that = this;
switch (_that) {
case _CompanyAccess():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CompanyAccess value)?  $default,){
final _that = this;
switch (_that) {
case _CompanyAccess() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String userId,  String companyId,  bool fullCompany, @JsonKey(includeFromJson: false, includeToJson: false)  List<String> siteIds,  bool canViewTransactions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CompanyAccess() when $default != null:
return $default(_that.userId,_that.companyId,_that.fullCompany,_that.siteIds,_that.canViewTransactions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String userId,  String companyId,  bool fullCompany, @JsonKey(includeFromJson: false, includeToJson: false)  List<String> siteIds,  bool canViewTransactions)  $default,) {final _that = this;
switch (_that) {
case _CompanyAccess():
return $default(_that.userId,_that.companyId,_that.fullCompany,_that.siteIds,_that.canViewTransactions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String userId,  String companyId,  bool fullCompany, @JsonKey(includeFromJson: false, includeToJson: false)  List<String> siteIds,  bool canViewTransactions)?  $default,) {final _that = this;
switch (_that) {
case _CompanyAccess() when $default != null:
return $default(_that.userId,_that.companyId,_that.fullCompany,_that.siteIds,_that.canViewTransactions);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CompanyAccess implements CompanyAccess {
  const _CompanyAccess({required this.userId, required this.companyId, this.fullCompany = true, @JsonKey(includeFromJson: false, includeToJson: false)  List<String> siteIds = const <String>[], this.canViewTransactions = true}): _siteIds = siteIds;
  factory _CompanyAccess.fromJson(Map<String, dynamic> json) => _$CompanyAccessFromJson(json);

@override final  String userId;
@override final  String companyId;
@override@JsonKey() final  bool fullCompany;
 final  List<String> _siteIds;
@override@JsonKey(includeFromJson: false, includeToJson: false) List<String> get siteIds {
  if (_siteIds is EqualUnmodifiableListView) return _siteIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_siteIds);
}

@override@JsonKey() final  bool canViewTransactions;

/// Create a copy of CompanyAccess
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CompanyAccessCopyWith<_CompanyAccess> get copyWith => __$CompanyAccessCopyWithImpl<_CompanyAccess>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CompanyAccessToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CompanyAccess&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.companyId, companyId) || other.companyId == companyId)&&(identical(other.fullCompany, fullCompany) || other.fullCompany == fullCompany)&&const DeepCollectionEquality().equals(other.siteIds, _siteIds)&&(identical(other.canViewTransactions, canViewTransactions) || other.canViewTransactions == canViewTransactions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,userId,companyId,fullCompany,const DeepCollectionEquality().hash(_siteIds),canViewTransactions);
}

@override
String toString() {
    return 'CompanyAccess(userId: $userId, companyId: $companyId, fullCompany: $fullCompany, siteIds: $siteIds, canViewTransactions: $canViewTransactions)';
}


}

/// @nodoc
abstract mixin class _$CompanyAccessCopyWith<$Res> implements $CompanyAccessCopyWith<$Res> {
  factory _$CompanyAccessCopyWith(_CompanyAccess value, $Res Function(_CompanyAccess) _then) = __$CompanyAccessCopyWithImpl;
@override @useResult
$Res call({
 String userId, String companyId, bool fullCompany,@JsonKey(includeFromJson: false, includeToJson: false) List<String> siteIds, bool canViewTransactions
});




}
/// @nodoc
class __$CompanyAccessCopyWithImpl<$Res>
    implements _$CompanyAccessCopyWith<$Res> {
  __$CompanyAccessCopyWithImpl(this._self, this._then);

  final _CompanyAccess _self;
  final $Res Function(_CompanyAccess) _then;

/// Create a copy of CompanyAccess
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? companyId = null,Object? fullCompany = null,Object? siteIds = null,Object? canViewTransactions = null,}) {
  return _then(_CompanyAccess(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,companyId: null == companyId ? _self.companyId : companyId // ignore: cast_nullable_to_non_nullable
as String,fullCompany: null == fullCompany ? _self.fullCompany : fullCompany // ignore: cast_nullable_to_non_nullable
as bool,siteIds: null == siteIds ? _self._siteIds : siteIds // ignore: cast_nullable_to_non_nullable
as List<String>,canViewTransactions: null == canViewTransactions ? _self.canViewTransactions : canViewTransactions // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
