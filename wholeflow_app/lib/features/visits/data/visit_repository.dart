import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/location/location_service.dart';
import '../../../core/providers.dart';
import '../domain/visit.dart';

/// Visit plans, the day's tasks and check-ins. Owners write plans directly
/// (RLS + a trigger checks the staff member and site); tasks are made by
/// `ensure_visit_tasks` and visits only by `check_in`.
class VisitRepository {
  VisitRepository(this._client);

  final SupabaseClient _client;

  static final _day = DateFormat('yyyy-MM-dd');

  /// Makes sure the plans have become tasks for these days (idempotent).
  Future<void> ensureTasks(DateTime from, DateTime to) async {
    try {
      await _client.rpc('ensure_visit_tasks', params: {'p_from': _day.format(from), 'p_to': _day.format(to)});
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Tasks from [from] to [to]; owners: one company (or all), staff: their own.
  Future<List<VisitTask>> tasks(DateTime from, DateTime to, {String? companyId, String? staffId}) async {
    try {
      await ensureTasks(from, to);
      final rows = await fetchAll((start, end) {
        var q = _client
            .from('v_visit_tasks')
            .select(VisitTask.columns)
            .gte('visit_date', _day.format(from))
            .lte('visit_date', _day.format(to));
        if (companyId != null) q = q.eq('company_id', companyId);
        if (staffId != null) q = q.eq('staff_id', staffId);
        return q
            .order('visit_date', ascending: false)
            .order('site_name', ascending: true)
            .order('shop_name', ascending: true)
            .order('task_id', ascending: true)
            .range(start, end);
      });
      return rows.map(VisitTask.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<List<VisitPlan>> plans(String companyId) async {
    try {
      final rows = await _client
          .from('visit_plans')
          .select(VisitPlan.columns)
          .eq('company_id', companyId)
          .order('active', ascending: false)
          .order('created_at', ascending: false);
      return rows.map(VisitPlan.fromJson).toList();
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
    final rows = date != null
        ? [
            {'site_id': siteId, 'staff_id': staffId, 'plan_date': _day.format(date)},
          ]
        : [
            for (final w in weekdays.toList()..sort())
              {
                'site_id': siteId,
                'staff_id': staffId,
                'weekday': w,
                'starts_on': _day.format(startsOn ?? DateTime.now()),
                'ends_on': endsOn == null ? null : _day.format(endsOn),
              },
          ];
    try {
      await _client.from('visit_plans').insert(rows);
    } catch (e) {
      throw _planFailure(e);
    }
  }

  Future<void> setPlanActive(String planId, bool active) async {
    try {
      await _client.from('visit_plans').update({'active': active}).eq('id', planId);
    } catch (e) {
      throw _planFailure(e);
    }
  }

  Future<void> deletePlan(String planId) async {
    try {
      await _client.from('visit_plans').delete().eq('id', planId);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<ShopVisit?> visit(String visitId) async {
    try {
      final row = await _client.from('shop_visits').select(ShopVisit.columns).eq('id', visitId).maybeSingle();
      return row == null ? null : ShopVisit.fromJson(row);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Refused check-ins for a task (owners only; staff get an empty list).
  Future<List<FailedAttempt>> failedAttempts(String taskId) async {
    try {
      final rows = await _client
          .from('visit_failed_attempts')
          .select(FailedAttempt.columns)
          .eq('task_id', taskId)
          .order('attempted_at', ascending: false);
      return rows.map(FailedAttempt.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<CheckInResult> checkIn(String taskId, LocationReading r, {required bool developerMode, String? note}) async {
    try {
      final res = await _client.rpc(
        'check_in',
        params: {
          'p_task_id': taskId,
          'p_lat': r.latitude,
          'p_lng': r.longitude,
          'p_accuracy_m': r.accuracyMeters,
          'p_is_mocked': r.isMocked,
          'p_developer_mode': developerMode,
          'p_note': note,
        },
      );
      return CheckInResult.fromJson(Map<String, dynamic>.from(res as Map));
    } on PostgrestException catch (e) {
      throw switch (e.code) {
        '23505' => const AppFailure(FailureKind.invalidInput, 'You have already checked in at this shop today.'),
        '22023' when e.message.contains('not for today') => const AppFailure(
          FailureKind.invalidInput,
          'This visit is not for today, so you cannot check in.',
        ),
        '42501' => const AppFailure(FailureKind.forbidden, 'You no longer have this shop. Ask your owner.'),
        _ => AppFailure.from(e),
      };
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> addNote(String visitId, String note) async {
    try {
      await _client.rpc('add_visit_note', params: {'p_visit_id': visitId, 'p_note': note});
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  static AppFailure _planFailure(Object e) {
    if (e is PostgrestException && e.code == '23514') {
      final m = e.message;
      if (m.contains('check-in')) {
        return const AppFailure(
          FailureKind.invalidInput,
          'Turn on "Must check in at shops" for this staff member first (Settings → Staff).',
        );
      }
      if (m.contains('does not have this site')) {
        return const AppFailure(FailureKind.invalidInput, 'This staff member does not have this site. Give it to them first.');
      }
    }
    return AppFailure.from(e);
  }
}

final visitRepositoryProvider = Provider<VisitRepository>((ref) => VisitRepository(ref.watch(supabaseProvider)));
