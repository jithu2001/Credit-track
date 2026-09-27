// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sync_health_repository.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TallyConnection {

 String get machineIdentifier; String? get hostname; String get status; String? get appVersion; DateTime? get lastSeenAt;
/// Create a copy of TallyConnection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TallyConnectionCopyWith<TallyConnection> get copyWith => _$TallyConnectionCopyWithImpl<TallyConnection>(this as TallyConnection, _$identity);

  /// Serializes this TallyConnection to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as TallyConnection;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TallyConnection&&(identical(other.machineIdentifier, _this.machineIdentifier) || other.machineIdentifier == _this.machineIdentifier)&&(identical(other.hostname, _this.hostname) || other.hostname == _this.hostname)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.appVersion, _this.appVersion) || other.appVersion == _this.appVersion)&&(identical(other.lastSeenAt, _this.lastSeenAt) || other.lastSeenAt == _this.lastSeenAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as TallyConnection;
  return Object.hash(runtimeType,_this.machineIdentifier,_this.hostname,_this.status,_this.appVersion,_this.lastSeenAt);
}

@override
String toString() {
  final _this = this as TallyConnection;
  return 'TallyConnection(machineIdentifier: ${_this.machineIdentifier}, hostname: ${_this.hostname}, status: ${_this.status}, appVersion: ${_this.appVersion}, lastSeenAt: ${_this.lastSeenAt})';
}


}

/// @nodoc
abstract mixin class $TallyConnectionCopyWith<$Res>  {
  factory $TallyConnectionCopyWith(TallyConnection value, $Res Function(TallyConnection) _then) = _$TallyConnectionCopyWithImpl;
@useResult
$Res call({
 String machineIdentifier, String? hostname, String status, String? appVersion, DateTime? lastSeenAt
});




}
/// @nodoc
class _$TallyConnectionCopyWithImpl<$Res>
    implements $TallyConnectionCopyWith<$Res> {
  _$TallyConnectionCopyWithImpl(this._self, this._then);

  final TallyConnection _self;
  final $Res Function(TallyConnection) _then;

/// Create a copy of TallyConnection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? machineIdentifier = null,Object? hostname = freezed,Object? status = null,Object? appVersion = freezed,Object? lastSeenAt = freezed,}) {
  return _then(TallyConnection(
machineIdentifier: null == machineIdentifier ? _self.machineIdentifier : machineIdentifier // ignore: cast_nullable_to_non_nullable
as String,hostname: freezed == hostname ? _self.hostname : hostname // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,appVersion: freezed == appVersion ? _self.appVersion : appVersion // ignore: cast_nullable_to_non_nullable
as String?,lastSeenAt: freezed == lastSeenAt ? _self.lastSeenAt : lastSeenAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [TallyConnection].
extension TallyConnectionPatterns on TallyConnection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TallyConnection value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TallyConnection() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TallyConnection value)  $default,){
final _that = this;
switch (_that) {
case _TallyConnection():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TallyConnection value)?  $default,){
final _that = this;
switch (_that) {
case _TallyConnection() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String machineIdentifier,  String? hostname,  String status,  String? appVersion,  DateTime? lastSeenAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TallyConnection() when $default != null:
return $default(_that.machineIdentifier,_that.hostname,_that.status,_that.appVersion,_that.lastSeenAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String machineIdentifier,  String? hostname,  String status,  String? appVersion,  DateTime? lastSeenAt)  $default,) {final _that = this;
switch (_that) {
case _TallyConnection():
return $default(_that.machineIdentifier,_that.hostname,_that.status,_that.appVersion,_that.lastSeenAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String machineIdentifier,  String? hostname,  String status,  String? appVersion,  DateTime? lastSeenAt)?  $default,) {final _that = this;
switch (_that) {
case _TallyConnection() when $default != null:
return $default(_that.machineIdentifier,_that.hostname,_that.status,_that.appVersion,_that.lastSeenAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TallyConnection implements TallyConnection {
  const _TallyConnection({required this.machineIdentifier, this.hostname, this.status = 'unknown', this.appVersion, this.lastSeenAt});
  factory _TallyConnection.fromJson(Map<String, dynamic> json) => _$TallyConnectionFromJson(json);

@override final  String machineIdentifier;
@override final  String? hostname;
@override@JsonKey() final  String status;
@override final  String? appVersion;
@override final  DateTime? lastSeenAt;

/// Create a copy of TallyConnection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TallyConnectionCopyWith<_TallyConnection> get copyWith => __$TallyConnectionCopyWithImpl<_TallyConnection>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TallyConnectionToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TallyConnection&&(identical(other.machineIdentifier, machineIdentifier) || other.machineIdentifier == machineIdentifier)&&(identical(other.hostname, hostname) || other.hostname == hostname)&&(identical(other.status, status) || other.status == status)&&(identical(other.appVersion, appVersion) || other.appVersion == appVersion)&&(identical(other.lastSeenAt, lastSeenAt) || other.lastSeenAt == lastSeenAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,machineIdentifier,hostname,status,appVersion,lastSeenAt);
}

@override
String toString() {
    return 'TallyConnection(machineIdentifier: $machineIdentifier, hostname: $hostname, status: $status, appVersion: $appVersion, lastSeenAt: $lastSeenAt)';
}


}

/// @nodoc
abstract mixin class _$TallyConnectionCopyWith<$Res> implements $TallyConnectionCopyWith<$Res> {
  factory _$TallyConnectionCopyWith(_TallyConnection value, $Res Function(_TallyConnection) _then) = __$TallyConnectionCopyWithImpl;
@override @useResult
$Res call({
 String machineIdentifier, String? hostname, String status, String? appVersion, DateTime? lastSeenAt
});




}
/// @nodoc
class __$TallyConnectionCopyWithImpl<$Res>
    implements _$TallyConnectionCopyWith<$Res> {
  __$TallyConnectionCopyWithImpl(this._self, this._then);

  final _TallyConnection _self;
  final $Res Function(_TallyConnection) _then;

/// Create a copy of TallyConnection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? machineIdentifier = null,Object? hostname = freezed,Object? status = null,Object? appVersion = freezed,Object? lastSeenAt = freezed,}) {
  return _then(_TallyConnection(
machineIdentifier: null == machineIdentifier ? _self.machineIdentifier : machineIdentifier // ignore: cast_nullable_to_non_nullable
as String,hostname: freezed == hostname ? _self.hostname : hostname // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,appVersion: freezed == appVersion ? _self.appVersion : appVersion // ignore: cast_nullable_to_non_nullable
as String?,lastSeenAt: freezed == lastSeenAt ? _self.lastSeenAt : lastSeenAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}


/// @nodoc
mixin _$SyncLogEntry {

 String get id; String? get companyId; DateTime get startedAt; DateTime? get completedAt; String get status; String? get mode; int get recordsProcessed; int get recordsCreated; int get recordsUpdated; int get recordsDeleted; int get recordsFailed; int get shopsProcessed; int get transactionsFetched; String? get errorCode; String? get errorMessage;
/// Create a copy of SyncLogEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncLogEntryCopyWith<SyncLogEntry> get copyWith => _$SyncLogEntryCopyWithImpl<SyncLogEntry>(this as SyncLogEntry, _$identity);

  /// Serializes this SyncLogEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SyncLogEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncLogEntry&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.companyId, _this.companyId) || other.companyId == _this.companyId)&&(identical(other.startedAt, _this.startedAt) || other.startedAt == _this.startedAt)&&(identical(other.completedAt, _this.completedAt) || other.completedAt == _this.completedAt)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.recordsProcessed, _this.recordsProcessed) || other.recordsProcessed == _this.recordsProcessed)&&(identical(other.recordsCreated, _this.recordsCreated) || other.recordsCreated == _this.recordsCreated)&&(identical(other.recordsUpdated, _this.recordsUpdated) || other.recordsUpdated == _this.recordsUpdated)&&(identical(other.recordsDeleted, _this.recordsDeleted) || other.recordsDeleted == _this.recordsDeleted)&&(identical(other.recordsFailed, _this.recordsFailed) || other.recordsFailed == _this.recordsFailed)&&(identical(other.shopsProcessed, _this.shopsProcessed) || other.shopsProcessed == _this.shopsProcessed)&&(identical(other.transactionsFetched, _this.transactionsFetched) || other.transactionsFetched == _this.transactionsFetched)&&(identical(other.errorCode, _this.errorCode) || other.errorCode == _this.errorCode)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SyncLogEntry;
  return Object.hash(runtimeType,_this.id,_this.companyId,_this.startedAt,_this.completedAt,_this.status,_this.mode,_this.recordsProcessed,_this.recordsCreated,_this.recordsUpdated,_this.recordsDeleted,_this.recordsFailed,_this.shopsProcessed,_this.transactionsFetched,_this.errorCode,_this.errorMessage);
}

@override
String toString() {
  final _this = this as SyncLogEntry;
  return 'SyncLogEntry(id: ${_this.id}, companyId: ${_this.companyId}, startedAt: ${_this.startedAt}, completedAt: ${_this.completedAt}, status: ${_this.status}, mode: ${_this.mode}, recordsProcessed: ${_this.recordsProcessed}, recordsCreated: ${_this.recordsCreated}, recordsUpdated: ${_this.recordsUpdated}, recordsDeleted: ${_this.recordsDeleted}, recordsFailed: ${_this.recordsFailed}, shopsProcessed: ${_this.shopsProcessed}, transactionsFetched: ${_this.transactionsFetched}, errorCode: ${_this.errorCode}, errorMessage: ${_this.errorMessage})';
}


}

/// @nodoc
abstract mixin class $SyncLogEntryCopyWith<$Res>  {
  factory $SyncLogEntryCopyWith(SyncLogEntry value, $Res Function(SyncLogEntry) _then) = _$SyncLogEntryCopyWithImpl;
@useResult
$Res call({
 String id, String? companyId, DateTime startedAt, DateTime? completedAt, String status, String? mode, int recordsProcessed, int recordsCreated, int recordsUpdated, int recordsDeleted, int recordsFailed, int shopsProcessed, int transactionsFetched, String? errorCode, String? errorMessage
});




}
/// @nodoc
class _$SyncLogEntryCopyWithImpl<$Res>
    implements $SyncLogEntryCopyWith<$Res> {
  _$SyncLogEntryCopyWithImpl(this._self, this._then);

  final SyncLogEntry _self;
  final $Res Function(SyncLogEntry) _then;

/// Create a copy of SyncLogEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? companyId = freezed,Object? startedAt = null,Object? completedAt = freezed,Object? status = null,Object? mode = freezed,Object? recordsProcessed = null,Object? recordsCreated = null,Object? recordsUpdated = null,Object? recordsDeleted = null,Object? recordsFailed = null,Object? shopsProcessed = null,Object? transactionsFetched = null,Object? errorCode = freezed,Object? errorMessage = freezed,}) {
  return _then(SyncLogEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,companyId: freezed == companyId ? _self.companyId : companyId // ignore: cast_nullable_to_non_nullable
as String?,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,mode: freezed == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String?,recordsProcessed: null == recordsProcessed ? _self.recordsProcessed : recordsProcessed // ignore: cast_nullable_to_non_nullable
as int,recordsCreated: null == recordsCreated ? _self.recordsCreated : recordsCreated // ignore: cast_nullable_to_non_nullable
as int,recordsUpdated: null == recordsUpdated ? _self.recordsUpdated : recordsUpdated // ignore: cast_nullable_to_non_nullable
as int,recordsDeleted: null == recordsDeleted ? _self.recordsDeleted : recordsDeleted // ignore: cast_nullable_to_non_nullable
as int,recordsFailed: null == recordsFailed ? _self.recordsFailed : recordsFailed // ignore: cast_nullable_to_non_nullable
as int,shopsProcessed: null == shopsProcessed ? _self.shopsProcessed : shopsProcessed // ignore: cast_nullable_to_non_nullable
as int,transactionsFetched: null == transactionsFetched ? _self.transactionsFetched : transactionsFetched // ignore: cast_nullable_to_non_nullable
as int,errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [SyncLogEntry].
extension SyncLogEntryPatterns on SyncLogEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SyncLogEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SyncLogEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SyncLogEntry value)  $default,){
final _that = this;
switch (_that) {
case _SyncLogEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SyncLogEntry value)?  $default,){
final _that = this;
switch (_that) {
case _SyncLogEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? companyId,  DateTime startedAt,  DateTime? completedAt,  String status,  String? mode,  int recordsProcessed,  int recordsCreated,  int recordsUpdated,  int recordsDeleted,  int recordsFailed,  int shopsProcessed,  int transactionsFetched,  String? errorCode,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SyncLogEntry() when $default != null:
return $default(_that.id,_that.companyId,_that.startedAt,_that.completedAt,_that.status,_that.mode,_that.recordsProcessed,_that.recordsCreated,_that.recordsUpdated,_that.recordsDeleted,_that.recordsFailed,_that.shopsProcessed,_that.transactionsFetched,_that.errorCode,_that.errorMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? companyId,  DateTime startedAt,  DateTime? completedAt,  String status,  String? mode,  int recordsProcessed,  int recordsCreated,  int recordsUpdated,  int recordsDeleted,  int recordsFailed,  int shopsProcessed,  int transactionsFetched,  String? errorCode,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _SyncLogEntry():
return $default(_that.id,_that.companyId,_that.startedAt,_that.completedAt,_that.status,_that.mode,_that.recordsProcessed,_that.recordsCreated,_that.recordsUpdated,_that.recordsDeleted,_that.recordsFailed,_that.shopsProcessed,_that.transactionsFetched,_that.errorCode,_that.errorMessage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? companyId,  DateTime startedAt,  DateTime? completedAt,  String status,  String? mode,  int recordsProcessed,  int recordsCreated,  int recordsUpdated,  int recordsDeleted,  int recordsFailed,  int shopsProcessed,  int transactionsFetched,  String? errorCode,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _SyncLogEntry() when $default != null:
return $default(_that.id,_that.companyId,_that.startedAt,_that.completedAt,_that.status,_that.mode,_that.recordsProcessed,_that.recordsCreated,_that.recordsUpdated,_that.recordsDeleted,_that.recordsFailed,_that.shopsProcessed,_that.transactionsFetched,_that.errorCode,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SyncLogEntry implements SyncLogEntry {
  const _SyncLogEntry({required this.id, this.companyId, required this.startedAt, this.completedAt, required this.status, this.mode, this.recordsProcessed = 0, this.recordsCreated = 0, this.recordsUpdated = 0, this.recordsDeleted = 0, this.recordsFailed = 0, this.shopsProcessed = 0, this.transactionsFetched = 0, this.errorCode, this.errorMessage});
  factory _SyncLogEntry.fromJson(Map<String, dynamic> json) => _$SyncLogEntryFromJson(json);

@override final  String id;
@override final  String? companyId;
@override final  DateTime startedAt;
@override final  DateTime? completedAt;
@override final  String status;
@override final  String? mode;
@override@JsonKey() final  int recordsProcessed;
@override@JsonKey() final  int recordsCreated;
@override@JsonKey() final  int recordsUpdated;
@override@JsonKey() final  int recordsDeleted;
@override@JsonKey() final  int recordsFailed;
@override@JsonKey() final  int shopsProcessed;
@override@JsonKey() final  int transactionsFetched;
@override final  String? errorCode;
@override final  String? errorMessage;

/// Create a copy of SyncLogEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SyncLogEntryCopyWith<_SyncLogEntry> get copyWith => __$SyncLogEntryCopyWithImpl<_SyncLogEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SyncLogEntryToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SyncLogEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.companyId, companyId) || other.companyId == companyId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.status, status) || other.status == status)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.recordsProcessed, recordsProcessed) || other.recordsProcessed == recordsProcessed)&&(identical(other.recordsCreated, recordsCreated) || other.recordsCreated == recordsCreated)&&(identical(other.recordsUpdated, recordsUpdated) || other.recordsUpdated == recordsUpdated)&&(identical(other.recordsDeleted, recordsDeleted) || other.recordsDeleted == recordsDeleted)&&(identical(other.recordsFailed, recordsFailed) || other.recordsFailed == recordsFailed)&&(identical(other.shopsProcessed, shopsProcessed) || other.shopsProcessed == shopsProcessed)&&(identical(other.transactionsFetched, transactionsFetched) || other.transactionsFetched == transactionsFetched)&&(identical(other.errorCode, errorCode) || other.errorCode == errorCode)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,companyId,startedAt,completedAt,status,mode,recordsProcessed,recordsCreated,recordsUpdated,recordsDeleted,recordsFailed,shopsProcessed,transactionsFetched,errorCode,errorMessage);
}

@override
String toString() {
    return 'SyncLogEntry(id: $id, companyId: $companyId, startedAt: $startedAt, completedAt: $completedAt, status: $status, mode: $mode, recordsProcessed: $recordsProcessed, recordsCreated: $recordsCreated, recordsUpdated: $recordsUpdated, recordsDeleted: $recordsDeleted, recordsFailed: $recordsFailed, shopsProcessed: $shopsProcessed, transactionsFetched: $transactionsFetched, errorCode: $errorCode, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$SyncLogEntryCopyWith<$Res> implements $SyncLogEntryCopyWith<$Res> {
  factory _$SyncLogEntryCopyWith(_SyncLogEntry value, $Res Function(_SyncLogEntry) _then) = __$SyncLogEntryCopyWithImpl;
@override @useResult
$Res call({
 String id, String? companyId, DateTime startedAt, DateTime? completedAt, String status, String? mode, int recordsProcessed, int recordsCreated, int recordsUpdated, int recordsDeleted, int recordsFailed, int shopsProcessed, int transactionsFetched, String? errorCode, String? errorMessage
});




}
/// @nodoc
class __$SyncLogEntryCopyWithImpl<$Res>
    implements _$SyncLogEntryCopyWith<$Res> {
  __$SyncLogEntryCopyWithImpl(this._self, this._then);

  final _SyncLogEntry _self;
  final $Res Function(_SyncLogEntry) _then;

/// Create a copy of SyncLogEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? companyId = freezed,Object? startedAt = null,Object? completedAt = freezed,Object? status = null,Object? mode = freezed,Object? recordsProcessed = null,Object? recordsCreated = null,Object? recordsUpdated = null,Object? recordsDeleted = null,Object? recordsFailed = null,Object? shopsProcessed = null,Object? transactionsFetched = null,Object? errorCode = freezed,Object? errorMessage = freezed,}) {
  return _then(_SyncLogEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,companyId: freezed == companyId ? _self.companyId : companyId // ignore: cast_nullable_to_non_nullable
as String?,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,mode: freezed == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String?,recordsProcessed: null == recordsProcessed ? _self.recordsProcessed : recordsProcessed // ignore: cast_nullable_to_non_nullable
as int,recordsCreated: null == recordsCreated ? _self.recordsCreated : recordsCreated // ignore: cast_nullable_to_non_nullable
as int,recordsUpdated: null == recordsUpdated ? _self.recordsUpdated : recordsUpdated // ignore: cast_nullable_to_non_nullable
as int,recordsDeleted: null == recordsDeleted ? _self.recordsDeleted : recordsDeleted // ignore: cast_nullable_to_non_nullable
as int,recordsFailed: null == recordsFailed ? _self.recordsFailed : recordsFailed // ignore: cast_nullable_to_non_nullable
as int,shopsProcessed: null == shopsProcessed ? _self.shopsProcessed : shopsProcessed // ignore: cast_nullable_to_non_nullable
as int,transactionsFetched: null == transactionsFetched ? _self.transactionsFetched : transactionsFetched // ignore: cast_nullable_to_non_nullable
as int,errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
