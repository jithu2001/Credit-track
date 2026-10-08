import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/location/location_service.dart';
import '../domain/visit.dart';

/// Visit plans, the day's tasks and check-ins, from the app API. Owners write
/// plans (the database checks the staff member and site); tasks are made from
/// the plans by the server and visits only by check-in.
class VisitRepository {
  VisitRepository(this._api);

  final ApiClient _api;

  static final _day = DateFormat('yyyy-MM-dd');

  /// Tasks from [from] to [to] (made from the plans first); owners: one
  /// company (or all), staff: their own.
  Future<List<VisitTask>> tasks(DateTime from, DateTime to, {String? companyId, String? staffId}) async {
    try {
      final body = await _api.get('visits/tasks', {
        'from': _day.format(from),
        'to': _day.format(to),
        'company': ?companyId,
        'staff': ?staffId,
      });
      return [for (final r in (body['tasks'] as List).cast<Map<String, dynamic>>()) VisitTask.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<List<VisitPlan>> plans(String companyId) async {
    try {
      final body = await _api.get('visits/plans', {'company': companyId});
      return [for (final r in (body['plans'] as List).cast<Map<String, dynamic>>()) VisitPlan.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// One plan per date, or one weekly plan per weekday.
  Future<void> createPlans({
    required String siteId,
    required String staffId,
    DateTime? date,
    Set<int> weekdays = const {},
    DateTime? startsOn,
    DateTime? endsOn,
  }) async {
    try {
      await _api.post('visits/plans', {
        'site': siteId,
        'staff': staffId,
        if (date != null) 'date': _day.format(date) else 'weekdays': weekdays.toList()..sort(),
        if (date == null) 'starts_on': _day.format(startsOn ?? DateTime.now()),
        if (date == null && endsOn != null) 'ends_on': _day.format(endsOn),
      });
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> setPlanActive(String planId, bool active) async {
    try {
      await _api.patch('visits/plans/$planId', {'active': active});
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> deletePlan(String planId) async {
    try {
      await _api.delete('visits/plans/$planId');
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<ShopVisit?> visit(String visitId) async {
    try {
      final row = (await _api.get('visits/$visitId'))['visit'];
      return row is Map<String, dynamic> ? ShopVisit.fromJson(row) : null;
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Refused check-ins for a task (owners only; staff get an empty list).
  Future<List<FailedAttempt>> failedAttempts(String taskId) async {
    try {
      final body = await _api.get('visits/tasks/$taskId/failed-attempts');
      return [for (final r in (body['attempts'] as List).cast<Map<String, dynamic>>()) FailedAttempt.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// The server refuses a second check-in at a shop the same day, a visit not
  /// for today and a shop the staff member no longer has, with a message.
  Future<CheckInResult> checkIn(String taskId, LocationReading r, {required bool developerMode, String? note}) async {
    try {
      return CheckInResult.fromJson(
        await _api.post('visits/tasks/$taskId/check-in', {
          'latitude': r.latitude,
          'longitude': r.longitude,
          'accuracy_m': r.accuracyMeters,
          'is_mocked': r.isMocked,
          'developer_mode': developerMode,
          'note': note,
        }),
      );
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> addNote(String visitId, String note) async {
    try {
      await _api.post('visits/$visitId/note', {'note': note});
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

final visitRepositoryProvider = Provider<VisitRepository>((ref) => VisitRepository(ref.watch(apiClientProvider)));
