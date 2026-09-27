import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_json.dart';

part 'dashboard_models.freezed.dart';
part 'dashboard_models.g.dart';

/// A row of `v_company_summary`. For staff the totals cover only their shops.
@freezed
abstract class CompanySummary with _$CompanySummary {
  const factory CompanySummary({
    required String companyId,
    required String companyName,
    @Default(0) int shops,
    @Default(0) int shopsWithDues,
    @MoneyConverter() @Default(Money.zero) Money totalOutstanding,
    @MoneyConverter() @Default(Money.zero) Money totalCredit,
  }) = _CompanySummary;

  factory CompanySummary.fromJson(Map<String, dynamic> json) => _$CompanySummaryFromJson(json);

  static const columns = 'company_id,company_name,shops,shops_with_dues,total_outstanding,total_credit';
}

/// The `sync_state` row with `entity_type = 'company'`.
@freezed
abstract class SyncState with _$SyncState {
  const factory SyncState({
    DateTime? lastSuccessfulSyncAt,
    DateTime? lastAttemptAt,
    @Default('ok') String status,
    String? errorCode,
    String? errorMessage,
  }) = _SyncState;

  factory SyncState.fromJson(Map<String, dynamic> json) => _$SyncStateFromJson(json);

  static const columns = 'last_successful_sync_at,last_attempt_at,status,error_code,error_message';
}

/// Sales bills to shops dated in one calendar month.
class MonthSales {
  const MonthSales({required this.month, required this.amount, required this.bills});

  /// First day of the month.
  final DateTime month;
  final Money amount;
  final int bills;
}

enum FreshnessLevel { fresh, warning }

/// What the freshness banner says.
class Freshness {
  const Freshness(this.level, this.headline, {this.detail});

  final FreshnessLevel level;
  final String headline;
  final String? detail;
}

/// Figures older than this are flagged even when the last sync succeeded.
const staleAfter = Duration(hours: 1);

/// Turns the sync bookkeeping into banner copy. [companySyncStatus] is
/// `tally_companies.sync_status` (PENDING, SYNCING, SYNCED, TALLY_OFFLINE, ...).
Freshness evaluateFreshness({required SyncState? state, required String companySyncStatus, required DateTime now}) {
  final last = state?.lastSuccessfulSyncAt;
  final updated = last == null ? 'Never updated' : 'Updated ${_ago(now.difference(last))}';

  final problem = switch (companySyncStatus) {
    'TALLY_OFFLINE' => 'Tally PC is offline — figures may be out of date',
    'CLOUD_OFFLINE' => "The Tally PC can't reach the internet — figures may be out of date",
    'AUTH_ERROR' => 'Cloud sync is not authorised — ask your administrator',
    'SYNC_ERROR' => 'The last sync failed — figures may be out of date',
    'COMPANY_NOT_OPEN' => 'This company is not open in Tally — figures may be out of date',
    'DISABLED' => 'Sync is turned off for this company',
    'PENDING' when last == null => 'Waiting for the first sync from Tally',
    _ => null,
  };
  if (problem != null) return Freshness(FreshnessLevel.warning, problem, detail: updated);
  if (state?.status == 'error') {
    return Freshness(FreshnessLevel.warning, 'The last sync had a problem — figures may be out of date', detail: updated);
  }
  if (last == null) return const Freshness(FreshnessLevel.warning, 'Waiting for the first sync from Tally');
  if (now.difference(last) > staleAfter) {
    return Freshness(FreshnessLevel.warning, 'Figures may be out of date', detail: updated);
  }
  return Freshness(FreshnessLevel.fresh, companySyncStatus == 'SYNCING' ? '$updated · syncing now' : updated);
}

String _ago(Duration d) {
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return d.inDays == 1 ? 'yesterday' : '${d.inDays} days ago';
}
