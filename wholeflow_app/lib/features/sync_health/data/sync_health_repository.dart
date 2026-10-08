import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/app_failure.dart';

part 'sync_health_repository.freezed.dart';
part 'sync_health_repository.g.dart';

/// The PC running the WholeFlow sync service (`tally_connections`, owners only).
@freezed
abstract class TallyConnection with _$TallyConnection {
  const factory TallyConnection({
    required String machineIdentifier,
    String? hostname,
    @Default('unknown') String status,
    String? appVersion,
    DateTime? lastSeenAt,
  }) = _TallyConnection;

  factory TallyConnection.fromJson(Map<String, dynamic> json) => _$TallyConnectionFromJson(json);

}

@freezed
abstract class SyncLogEntry with _$SyncLogEntry {
  const factory SyncLogEntry({
    required String id,
    String? companyId,
    required DateTime startedAt,
    DateTime? completedAt,
    required String status,
    String? mode,
    @Default(0) int recordsProcessed,
    @Default(0) int recordsCreated,
    @Default(0) int recordsUpdated,
    @Default(0) int recordsDeleted,
    @Default(0) int recordsFailed,
    @Default(0) int shopsProcessed,
    @Default(0) int transactionsFetched,
    String? errorCode,
    String? errorMessage,
  }) = _SyncLogEntry;

  factory SyncLogEntry.fromJson(Map<String, dynamic> json) => _$SyncLogEntryFromJson(json);

}

class SyncHealthRepository {
  SyncHealthRepository(this._api);

  final ApiClient _api;

  Future<List<TallyConnection>> connections() async {
    try {
      final body = await _api.get('sync/connections');
      return [for (final r in (body['connections'] as List).cast<Map<String, dynamic>>()) TallyConnection.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<List<SyncLogEntry>> recentLogs({int limit = 20}) async {
    try {
      final body = await _api.get('sync/logs', {'limit': '$limit'});
      return [for (final r in (body['logs'] as List).cast<Map<String, dynamic>>()) SyncLogEntry.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
SyncHealthRepository syncHealthRepository(Ref ref) => SyncHealthRepository(ref.watch(apiClientProvider));

@riverpod
Future<List<TallyConnection>> tallyConnections(Ref ref) => ref.watch(syncHealthRepositoryProvider).connections();

@riverpod
Future<List<SyncLogEntry>> recentSyncLogs(Ref ref) => ref.watch(syncHealthRepositoryProvider).recentLogs();
