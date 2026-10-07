import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/presentation/session_controller.dart';
import '../data/visit_repository.dart';
import '../domain/visit.dart';

part 'visit_providers.g.dart';

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// The day the owner's Visits view shows. A view setting only.
@Riverpod(keepAlive: true)
class VisitDayController extends _$VisitDayController {
  @override
  DateTime build() => _dayOf(DateTime.now());

  void set(DateTime d) => state = _dayOf(d);
  void shift(int days) => state = _dayOf(state.add(Duration(days: days)));
}

/// Owner: every task of one company on one day.
@riverpod
Future<List<VisitTask>> companyDayTasks(Ref ref, String companyId, DateTime day) =>
    ref.watch(visitRepositoryProvider).tasks(day, day, companyId: companyId);

/// Staff: my tasks for today.
@riverpod
Future<List<VisitTask>> myTodayTasks(Ref ref) {
  final user = ref.watch(currentUserProvider);
  final today = _dayOf(DateTime.now());
  if (user == null) return Future.value(const []);
  return ref.watch(visitRepositoryProvider).tasks(today, today, staffId: user.id);
}

/// Staff: my last 30 days, newest first.
@riverpod
Future<List<VisitTask>> myHistory(Ref ref) {
  final user = ref.watch(currentUserProvider);
  final today = _dayOf(DateTime.now());
  if (user == null) return Future.value(const []);
  return ref.watch(visitRepositoryProvider).tasks(today.subtract(const Duration(days: 30)), today, staffId: user.id);
}

/// Owner: one staff member's last 30 days.
@riverpod
Future<List<VisitTask>> staffHistory(Ref ref, String staffId) {
  final today = _dayOf(DateTime.now());
  return ref.watch(visitRepositoryProvider).tasks(today.subtract(const Duration(days: 30)), today, staffId: staffId);
}

@riverpod
Future<List<VisitPlan>> visitPlans(Ref ref, String companyId) => ref.watch(visitRepositoryProvider).plans(companyId);

@riverpod
Future<ShopVisit?> shopVisit(Ref ref, String visitId) => ref.watch(visitRepositoryProvider).visit(visitId);

@riverpod
Future<List<FailedAttempt>> failedAttempts(Ref ref, String taskId) => ref.watch(visitRepositoryProvider).failedAttempts(taskId);
