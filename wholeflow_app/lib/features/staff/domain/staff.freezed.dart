// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'staff.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$StaffMember {

 String get id; UserRole get role; String get name; String? get email; bool get isActive; bool get requiresCheckIn; DateTime? get createdAt;@JsonKey(includeFromJson: false, includeToJson: false) List<CompanyAccess> get companies;
/// Create a copy of StaffMember
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StaffMemberCopyWith<StaffMember> get copyWith => _$StaffMemberCopyWithImpl<StaffMember>(this as StaffMember, _$identity);

  /// Serializes this StaffMember to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as StaffMember;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StaffMember&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.role, _this.role) || other.role == _this.role)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.email, _this.email) || other.email == _this.email)&&(identical(other.isActive, _this.isActive) || other.isActive == _this.isActive)&&(identical(other.requiresCheckIn, _this.requiresCheckIn) || other.requiresCheckIn == _this.requiresCheckIn)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&const DeepCollectionEquality().equals(other.companies, _this.companies));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as StaffMember;
  return Object.hash(runtimeType,_this.id,_this.role,_this.name,_this.email,_this.isActive,_this.requiresCheckIn,_this.createdAt,const DeepCollectionEquality().hash(_this.companies));
}

@override
String toString() {
  final _this = this as StaffMember;
  return 'StaffMember(id: ${_this.id}, role: ${_this.role}, name: ${_this.name}, email: ${_this.email}, isActive: ${_this.isActive}, requiresCheckIn: ${_this.requiresCheckIn}, createdAt: ${_this.createdAt}, companies: ${_this.companies})';
}


}

/// @nodoc
abstract mixin class $StaffMemberCopyWith<$Res>  {
  factory $StaffMemberCopyWith(StaffMember value, $Res Function(StaffMember) _then) = _$StaffMemberCopyWithImpl;
@useResult
$Res call({
 String id, UserRole role, String name, String? email, bool isActive, bool requiresCheckIn, DateTime? createdAt,@JsonKey(includeFromJson: false, includeToJson: false) List<CompanyAccess> companies
});




}
/// @nodoc
class _$StaffMemberCopyWithImpl<$Res>
    implements $StaffMemberCopyWith<$Res> {
  _$StaffMemberCopyWithImpl(this._self, this._then);

  final StaffMember _self;
  final $Res Function(StaffMember) _then;

/// Create a copy of StaffMember
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? role = null,Object? name = null,Object? email = freezed,Object? isActive = null,Object? requiresCheckIn = null,Object? createdAt = freezed,Object? companies = null,}) {
  return _then(StaffMember(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as UserRole,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,requiresCheckIn: null == requiresCheckIn ? _self.requiresCheckIn : requiresCheckIn // ignore: cast_nullable_to_non_nullable
as bool,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,companies: null == companies ? _self.companies : companies // ignore: cast_nullable_to_non_nullable
as List<CompanyAccess>,
  ));
}

}


/// Adds pattern-matching-related methods to [StaffMember].
extension StaffMemberPatterns on StaffMember {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StaffMember value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StaffMember() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StaffMember value)  $default,){
final _that = this;
switch (_that) {
case _StaffMember():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StaffMember value)?  $default,){
final _that = this;
switch (_that) {
case _StaffMember() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  UserRole role,  String name,  String? email,  bool isActive,  bool requiresCheckIn,  DateTime? createdAt, @JsonKey(includeFromJson: false, includeToJson: false)  List<CompanyAccess> companies)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StaffMember() when $default != null:
return $default(_that.id,_that.role,_that.name,_that.email,_that.isActive,_that.requiresCheckIn,_that.createdAt,_that.companies);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  UserRole role,  String name,  String? email,  bool isActive,  bool requiresCheckIn,  DateTime? createdAt, @JsonKey(includeFromJson: false, includeToJson: false)  List<CompanyAccess> companies)  $default,) {final _that = this;
switch (_that) {
case _StaffMember():
return $default(_that.id,_that.role,_that.name,_that.email,_that.isActive,_that.requiresCheckIn,_that.createdAt,_that.companies);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  UserRole role,  String name,  String? email,  bool isActive,  bool requiresCheckIn,  DateTime? createdAt, @JsonKey(includeFromJson: false, includeToJson: false)  List<CompanyAccess> companies)?  $default,) {final _that = this;
switch (_that) {
case _StaffMember() when $default != null:
return $default(_that.id,_that.role,_that.name,_that.email,_that.isActive,_that.requiresCheckIn,_that.createdAt,_that.companies);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _StaffMember extends StaffMember {
  const _StaffMember({required this.id, required this.role, this.name = '', this.email, this.isActive = true, this.requiresCheckIn = false, this.createdAt, @JsonKey(includeFromJson: false, includeToJson: false)  List<CompanyAccess> companies = const <CompanyAccess>[]}): _companies = companies,super._();
  factory _StaffMember.fromJson(Map<String, dynamic> json) => _$StaffMemberFromJson(json);

@override final  String id;
@override final  UserRole role;
@override@JsonKey() final  String name;
@override final  String? email;
@override@JsonKey() final  bool isActive;
@override@JsonKey() final  bool requiresCheckIn;
@override final  DateTime? createdAt;
 final  List<CompanyAccess> _companies;
@override@JsonKey(includeFromJson: false, includeToJson: false) List<CompanyAccess> get companies {
  if (_companies is EqualUnmodifiableListView) return _companies;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_companies);
}


/// Create a copy of StaffMember
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StaffMemberCopyWith<_StaffMember> get copyWith => __$StaffMemberCopyWithImpl<_StaffMember>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$StaffMemberToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StaffMember&&(identical(other.id, id) || other.id == id)&&(identical(other.role, role) || other.role == role)&&(identical(other.name, name) || other.name == name)&&(identical(other.email, email) || other.email == email)&&(identical(other.isActive, isActive) || other.isActive == isActive)&&(identical(other.requiresCheckIn, requiresCheckIn) || other.requiresCheckIn == requiresCheckIn)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other.companies, _companies));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,role,name,email,isActive,requiresCheckIn,createdAt,const DeepCollectionEquality().hash(_companies));
}

@override
String toString() {
    return 'StaffMember(id: $id, role: $role, name: $name, email: $email, isActive: $isActive, requiresCheckIn: $requiresCheckIn, createdAt: $createdAt, companies: $companies)';
}


}

/// @nodoc
abstract mixin class _$StaffMemberCopyWith<$Res> implements $StaffMemberCopyWith<$Res> {
  factory _$StaffMemberCopyWith(_StaffMember value, $Res Function(_StaffMember) _then) = __$StaffMemberCopyWithImpl;
@override @useResult
$Res call({
 String id, UserRole role, String name, String? email, bool isActive, bool requiresCheckIn, DateTime? createdAt,@JsonKey(includeFromJson: false, includeToJson: false) List<CompanyAccess> companies
});




}
/// @nodoc
class __$StaffMemberCopyWithImpl<$Res>
    implements _$StaffMemberCopyWith<$Res> {
  __$StaffMemberCopyWithImpl(this._self, this._then);

  final _StaffMember _self;
  final $Res Function(_StaffMember) _then;

/// Create a copy of StaffMember
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? role = null,Object? name = null,Object? email = freezed,Object? isActive = null,Object? requiresCheckIn = null,Object? createdAt = freezed,Object? companies = null,}) {
  return _then(_StaffMember(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as UserRole,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,requiresCheckIn: null == requiresCheckIn ? _self.requiresCheckIn : requiresCheckIn // ignore: cast_nullable_to_non_nullable
as bool,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,companies: null == companies ? _self._companies : companies // ignore: cast_nullable_to_non_nullable
as List<CompanyAccess>,
  ));
}


}

/// @nodoc
mixin _$CompanyGrant {

 String get companyId; bool get fullCompany; Set<String> get siteIds; bool get canViewTransactions;
/// Create a copy of CompanyGrant
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CompanyGrantCopyWith<CompanyGrant> get copyWith => _$CompanyGrantCopyWithImpl<CompanyGrant>(this as CompanyGrant, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CompanyGrant;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CompanyGrant&&(identical(other.companyId, _this.companyId) || other.companyId == _this.companyId)&&(identical(other.fullCompany, _this.fullCompany) || other.fullCompany == _this.fullCompany)&&const DeepCollectionEquality().equals(other.siteIds, _this.siteIds)&&(identical(other.canViewTransactions, _this.canViewTransactions) || other.canViewTransactions == _this.canViewTransactions));
}


@override
int get hashCode {
  final _this = this as CompanyGrant;
  return Object.hash(runtimeType,_this.companyId,_this.fullCompany,const DeepCollectionEquality().hash(_this.siteIds),_this.canViewTransactions);
}

@override
String toString() {
  final _this = this as CompanyGrant;
  return 'CompanyGrant(companyId: ${_this.companyId}, fullCompany: ${_this.fullCompany}, siteIds: ${_this.siteIds}, canViewTransactions: ${_this.canViewTransactions})';
}


}

/// @nodoc
abstract mixin class $CompanyGrantCopyWith<$Res>  {
  factory $CompanyGrantCopyWith(CompanyGrant value, $Res Function(CompanyGrant) _then) = _$CompanyGrantCopyWithImpl;
@useResult
$Res call({
 String companyId, bool fullCompany, Set<String> siteIds, bool canViewTransactions
});




}
/// @nodoc
class _$CompanyGrantCopyWithImpl<$Res>
    implements $CompanyGrantCopyWith<$Res> {
  _$CompanyGrantCopyWithImpl(this._self, this._then);

  final CompanyGrant _self;
  final $Res Function(CompanyGrant) _then;

/// Create a copy of CompanyGrant
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? companyId = null,Object? fullCompany = null,Object? siteIds = null,Object? canViewTransactions = null,}) {
  return _then(CompanyGrant(
companyId: null == companyId ? _self.companyId : companyId // ignore: cast_nullable_to_non_nullable
as String,fullCompany: null == fullCompany ? _self.fullCompany : fullCompany // ignore: cast_nullable_to_non_nullable
as bool,siteIds: null == siteIds ? _self.siteIds : siteIds // ignore: cast_nullable_to_non_nullable
as Set<String>,canViewTransactions: null == canViewTransactions ? _self.canViewTransactions : canViewTransactions // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [CompanyGrant].
extension CompanyGrantPatterns on CompanyGrant {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CompanyGrant value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CompanyGrant() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CompanyGrant value)  $default,){
final _that = this;
switch (_that) {
case _CompanyGrant():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CompanyGrant value)?  $default,){
final _that = this;
switch (_that) {
case _CompanyGrant() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String companyId,  bool fullCompany,  Set<String> siteIds,  bool canViewTransactions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CompanyGrant() when $default != null:
return $default(_that.companyId,_that.fullCompany,_that.siteIds,_that.canViewTransactions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String companyId,  bool fullCompany,  Set<String> siteIds,  bool canViewTransactions)  $default,) {final _that = this;
switch (_that) {
case _CompanyGrant():
return $default(_that.companyId,_that.fullCompany,_that.siteIds,_that.canViewTransactions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String companyId,  bool fullCompany,  Set<String> siteIds,  bool canViewTransactions)?  $default,) {final _that = this;
switch (_that) {
case _CompanyGrant() when $default != null:
return $default(_that.companyId,_that.fullCompany,_that.siteIds,_that.canViewTransactions);case _:
  return null;

}
}

}

/// @nodoc


class _CompanyGrant extends CompanyGrant {
  const _CompanyGrant({required this.companyId, this.fullCompany = true,  Set<String> siteIds = const <String>{}, this.canViewTransactions = true}): _siteIds = siteIds,super._();
  

@override final  String companyId;
@override@JsonKey() final  bool fullCompany;
 final  Set<String> _siteIds;
@override@JsonKey() Set<String> get siteIds {
  if (_siteIds is EqualUnmodifiableSetView) return _siteIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_siteIds);
}

@override@JsonKey() final  bool canViewTransactions;

/// Create a copy of CompanyGrant
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CompanyGrantCopyWith<_CompanyGrant> get copyWith => __$CompanyGrantCopyWithImpl<_CompanyGrant>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CompanyGrant&&(identical(other.companyId, companyId) || other.companyId == companyId)&&(identical(other.fullCompany, fullCompany) || other.fullCompany == fullCompany)&&const DeepCollectionEquality().equals(other.siteIds, _siteIds)&&(identical(other.canViewTransactions, canViewTransactions) || other.canViewTransactions == canViewTransactions));
}


@override
int get hashCode {
    return Object.hash(runtimeType,companyId,fullCompany,const DeepCollectionEquality().hash(_siteIds),canViewTransactions);
}

@override
String toString() {
    return 'CompanyGrant(companyId: $companyId, fullCompany: $fullCompany, siteIds: $siteIds, canViewTransactions: $canViewTransactions)';
}


}

/// @nodoc
abstract mixin class _$CompanyGrantCopyWith<$Res> implements $CompanyGrantCopyWith<$Res> {
  factory _$CompanyGrantCopyWith(_CompanyGrant value, $Res Function(_CompanyGrant) _then) = __$CompanyGrantCopyWithImpl;
@override @useResult
$Res call({
 String companyId, bool fullCompany, Set<String> siteIds, bool canViewTransactions
});




}
/// @nodoc
class __$CompanyGrantCopyWithImpl<$Res>
    implements _$CompanyGrantCopyWith<$Res> {
  __$CompanyGrantCopyWithImpl(this._self, this._then);

  final _CompanyGrant _self;
  final $Res Function(_CompanyGrant) _then;

/// Create a copy of CompanyGrant
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? companyId = null,Object? fullCompany = null,Object? siteIds = null,Object? canViewTransactions = null,}) {
  return _then(_CompanyGrant(
companyId: null == companyId ? _self.companyId : companyId // ignore: cast_nullable_to_non_nullable
as String,fullCompany: null == fullCompany ? _self.fullCompany : fullCompany // ignore: cast_nullable_to_non_nullable
as bool,siteIds: null == siteIds ? _self._siteIds : siteIds // ignore: cast_nullable_to_non_nullable
as Set<String>,canViewTransactions: null == canViewTransactions ? _self.canViewTransactions : canViewTransactions // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
