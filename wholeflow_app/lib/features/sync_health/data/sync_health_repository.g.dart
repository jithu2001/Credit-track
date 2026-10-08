// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_health_repository.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TallyConnection _$TallyConnectionFromJson(Map<String, dynamic> json) =>
    _TallyConnection(
      machineIdentifier: json['machine_identifier'] as String,
      hostname: json['hostname'] as String?,
      status: json['status'] as String? ?? 'unknown',
      appVersion: json['app_version'] as String?,
      lastSeenAt: json['last_seen_at'] == null
          ? null
          : DateTime.parse(json['last_seen_at'] as String),
    );

Map<String, dynamic> _$TallyConnectionToJson(_TallyConnection instance) =>
    <String, dynamic>{
      'machine_identifier': instance.machineIdentifier,
      'hostname': instance.hostname,
      'status': instance.status,
      'app_version': instance.appVersion,
      'last_seen_at': instance.lastSeenAt?.toIso8601String(),
    };

_SyncLogEntry _$SyncLogEntryFromJson(Map<String, dynamic> json) =>
    _SyncLogEntry(
      id: json['id'] as String,
      companyId: json['company_id'] as String?,
      startedAt: DateTime.parse(json['started_at'] as String),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
      status: json['status'] as String,
      mode: json['mode'] as String?,
      recordsProcessed: (json['records_processed'] as num?)?.toInt() ?? 0,
      recordsCreated: (json['records_created'] as num?)?.toInt() ?? 0,
      recordsUpdated: (json['records_updated'] as num?)?.toInt() ?? 0,
      recordsDeleted: (json['records_deleted'] as num?)?.toInt() ?? 0,
      recordsFailed: (json['records_failed'] as num?)?.toInt() ?? 0,
      shopsProcessed: (json['shops_processed'] as num?)?.toInt() ?? 0,
      transactionsFetched: (json['transactions_fetched'] as num?)?.toInt() ?? 0,
      errorCode: json['error_code'] as String?,
      errorMessage: json['error_message'] as String?,
    );

Map<String, dynamic> _$SyncLogEntryToJson(_SyncLogEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'company_id': instance.companyId,
      'started_at': instance.startedAt.toIso8601String(),
      'completed_at': instance.completedAt?.toIso8601String(),
      'status': instance.status,
      'mode': instance.mode,
      'records_processed': instance.recordsProcessed,
      'records_created': instance.recordsCreated,
      'records_updated': instance.recordsUpdated,
      'records_deleted': instance.recordsDeleted,
      'records_failed': instance.recordsFailed,
      'shops_processed': instance.shopsProcessed,
      'transactions_fetched': instance.transactionsFetched,
      'error_code': instance.errorCode,
      'error_message': instance.errorMessage,
    };

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(syncHealthRepository)
final syncHealthRepositoryProvider = SyncHealthRepositoryProvider._();

final class SyncHealthRepositoryProvider
    extends
        $FunctionalProvider<
          SyncHealthRepository,
          SyncHealthRepository,
          SyncHealthRepository
        >
    with $Provider<SyncHealthRepository> {
  SyncHealthRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncHealthRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncHealthRepositoryHash();

  @$internal
  @override
  $ProviderElement<SyncHealthRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SyncHealthRepository create(Ref ref) {
    return syncHealthRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncHealthRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncHealthRepository>(value),
    );
  }
}

String _$syncHealthRepositoryHash() =>
    r'2d705c3174015811dc30e6a456360bdccbc35d91';

@ProviderFor(tallyConnections)
final tallyConnectionsProvider = TallyConnectionsProvider._();

final class TallyConnectionsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TallyConnection>>,
          List<TallyConnection>,
          FutureOr<List<TallyConnection>>
        >
    with
        $FutureModifier<List<TallyConnection>>,
        $FutureProvider<List<TallyConnection>> {
  TallyConnectionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tallyConnectionsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tallyConnectionsHash();

  @$internal
  @override
  $FutureProviderElement<List<TallyConnection>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<TallyConnection>> create(Ref ref) {
    return tallyConnections(ref);
  }
}

String _$tallyConnectionsHash() => r'6355b3e4f3d75079d30e754f2424600cb26c06b2';

@ProviderFor(recentSyncLogs)
final recentSyncLogsProvider = RecentSyncLogsProvider._();

final class RecentSyncLogsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SyncLogEntry>>,
          List<SyncLogEntry>,
          FutureOr<List<SyncLogEntry>>
        >
    with
        $FutureModifier<List<SyncLogEntry>>,
        $FutureProvider<List<SyncLogEntry>> {
  RecentSyncLogsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recentSyncLogsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recentSyncLogsHash();

  @$internal
  @override
  $FutureProviderElement<List<SyncLogEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<SyncLogEntry>> create(Ref ref) {
    return recentSyncLogs(ref);
  }
}

String _$recentSyncLogsHash() => r'266d894ab033597e06d34e1a434eb2e87647a164';
