import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/providers.dart';

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

  static const columns = 'machine_identifier,hostname,status,app_version,last_seen_at';
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

  static const columns =
      'id,company_id,started_at,completed_at,status,mode,records_processed,records_created,'
      'records_updated,records_deleted,records_failed,shops_processed,transactions_fetched,error_code,error_message';
}

class SyncHealthRepository {
  SyncHealthRepository(this._client);

  final SupabaseClient _client;

  Future<List<TallyConnection>> connections() async {
    try {
      final rows = await _client
          .from('tally_connections')
          .select(TallyConnection.columns)
          .order('last_seen_at', ascending: false);
      return rows.map(TallyConnection.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<List<SyncLogEntry>> recentLogs({int limit = 20}) async {
    try {
      final rows = await _client
          .from('sync_logs')
          .select(SyncLogEntry.columns)
          .order('started_at', ascending: false)
          .limit(limit);
      return rows.map(SyncLogEntry.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
SyncHealthRepository syncHealthRepository(Ref ref) => SyncHealthRepository(ref.watch(supabaseProvider));

@riverpod
Future<List<TallyConnection>> tallyConnections(Ref ref) => ref.watch(syncHealthRepositoryProvider).connections();

@riverpod
Future<List<SyncLogEntry>> recentSyncLogs(Ref ref) => ref.watch(syncHealthRepositoryProvider).recentLogs();
