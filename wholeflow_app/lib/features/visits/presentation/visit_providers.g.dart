// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'visit_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The day the owner's Visits view shows. A view setting only.

@ProviderFor(VisitDayController)
final visitDayControllerProvider = VisitDayControllerProvider._();

/// The day the owner's Visits view shows. A view setting only.
final class VisitDayControllerProvider extends $NotifierProvider<VisitDayController, DateTime> {
  /// The day the owner's Visits view shows. A view setting only.
  VisitDayControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'visitDayControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$visitDayControllerHash();

  @$internal
  @override
  VisitDayController create() => VisitDayController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<DateTime>(value));
  }
}

String _$visitDayControllerHash() => r'979cfcee6e17cd2ce65088ccaa94393a740d412b';

/// The day the owner's Visits view shows. A view setting only.

abstract class _$VisitDayController extends $Notifier<DateTime> {
  DateTime build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DateTime, DateTime>;
    final element = ref.element as $ClassProviderElement<AnyNotifier<DateTime, DateTime>, DateTime, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}

/// Owner: every task of one company on one day.

@ProviderFor(companyDayTasks)
final companyDayTasksProvider = CompanyDayTasksFamily._();

/// Owner: every task of one company on one day.

final class CompanyDayTasksProvider
    extends $FunctionalProvider<AsyncValue<List<VisitTask>>, List<VisitTask>, FutureOr<List<VisitTask>>>
    with $FutureModifier<List<VisitTask>>, $FutureProvider<List<VisitTask>> {
  /// Owner: every task of one company on one day.
  CompanyDayTasksProvider._({required CompanyDayTasksFamily super.from, required (String, DateTime) super.argument})
    : super(
        retry: null,
        name: r'companyDayTasksProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$companyDayTasksHash();

  @override
  String toString() {
    return r'companyDayTasksProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<VisitTask>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<VisitTask>> create(Ref ref) {
    final argument = this.argument as (String, DateTime);
    return companyDayTasks(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is CompanyDayTasksProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$companyDayTasksHash() => r'cdb110b08f98eb70a436f98affeb14d1d03a02b0';

/// Owner: every task of one company on one day.

final class CompanyDayTasksFamily extends $Family with $FunctionalFamilyOverride<FutureOr<List<VisitTask>>, (String, DateTime)> {
  CompanyDayTasksFamily._()
    : super(
        retry: null,
        name: r'companyDayTasksProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Owner: every task of one company on one day.

  CompanyDayTasksProvider call(String companyId, DateTime day) =>
      CompanyDayTasksProvider._(argument: (companyId, day), from: this);

  @override
  String toString() => r'companyDayTasksProvider';
}

/// Staff: my tasks for today.

@ProviderFor(myTodayTasks)
final myTodayTasksProvider = MyTodayTasksProvider._();

/// Staff: my tasks for today.

final class MyTodayTasksProvider
    extends $FunctionalProvider<AsyncValue<List<VisitTask>>, List<VisitTask>, FutureOr<List<VisitTask>>>
    with $FutureModifier<List<VisitTask>>, $FutureProvider<List<VisitTask>> {
  /// Staff: my tasks for today.
  MyTodayTasksProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myTodayTasksProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myTodayTasksHash();

  @$internal
  @override
  $FutureProviderElement<List<VisitTask>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<VisitTask>> create(Ref ref) {
    return myTodayTasks(ref);
  }
}

String _$myTodayTasksHash() => r'35dbc2e67dea9c9c247579307fd2dc989bf1a1fa';

/// Staff: my last 30 days, newest first.

@ProviderFor(myHistory)
final myHistoryProvider = MyHistoryProvider._();

/// Staff: my last 30 days, newest first.

final class MyHistoryProvider extends $FunctionalProvider<AsyncValue<List<VisitTask>>, List<VisitTask>, FutureOr<List<VisitTask>>>
    with $FutureModifier<List<VisitTask>>, $FutureProvider<List<VisitTask>> {
  /// Staff: my last 30 days, newest first.
  MyHistoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myHistoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myHistoryHash();

  @$internal
  @override
  $FutureProviderElement<List<VisitTask>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<VisitTask>> create(Ref ref) {
    return myHistory(ref);
  }
}

String _$myHistoryHash() => r'd4216d1371d5e78e21af7ca106f05c010a1d2aeb';

/// Owner: one staff member's last 30 days.

@ProviderFor(staffHistory)
final staffHistoryProvider = StaffHistoryFamily._();

/// Owner: one staff member's last 30 days.

final class StaffHistoryProvider
    extends $FunctionalProvider<AsyncValue<List<VisitTask>>, List<VisitTask>, FutureOr<List<VisitTask>>>
    with $FutureModifier<List<VisitTask>>, $FutureProvider<List<VisitTask>> {
  /// Owner: one staff member's last 30 days.
  StaffHistoryProvider._({required StaffHistoryFamily super.from, required String super.argument})
    : super(
        retry: null,
        name: r'staffHistoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$staffHistoryHash();

  @override
  String toString() {
    return r'staffHistoryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<VisitTask>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<VisitTask>> create(Ref ref) {
    final argument = this.argument as String;
    return staffHistory(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is StaffHistoryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$staffHistoryHash() => r'8b2ad90a3781a76c0e684dca2f1219505b7adffe';

/// Owner: one staff member's last 30 days.

final class StaffHistoryFamily extends $Family with $FunctionalFamilyOverride<FutureOr<List<VisitTask>>, String> {
  StaffHistoryFamily._()
    : super(
        retry: null,
        name: r'staffHistoryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Owner: one staff member's last 30 days.

  StaffHistoryProvider call(String staffId) => StaffHistoryProvider._(argument: staffId, from: this);

  @override
  String toString() => r'staffHistoryProvider';
}

@ProviderFor(visitPlans)
final visitPlansProvider = VisitPlansFamily._();

final class VisitPlansProvider
    extends $FunctionalProvider<AsyncValue<List<VisitPlan>>, List<VisitPlan>, FutureOr<List<VisitPlan>>>
    with $FutureModifier<List<VisitPlan>>, $FutureProvider<List<VisitPlan>> {
  VisitPlansProvider._({required VisitPlansFamily super.from, required String super.argument})
    : super(retry: null, name: r'visitPlansProvider', isAutoDispose: true, dependencies: null, $allTransitiveDependencies: null);

  @override
  String debugGetCreateSourceHash() => _$visitPlansHash();

  @override
  String toString() {
    return r'visitPlansProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<VisitPlan>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<VisitPlan>> create(Ref ref) {
    final argument = this.argument as String;
    return visitPlans(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is VisitPlansProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$visitPlansHash() => r'2e30dff931cee48651e21a4b7d31014ccd37f1de';

final class VisitPlansFamily extends $Family with $FunctionalFamilyOverride<FutureOr<List<VisitPlan>>, String> {
  VisitPlansFamily._()
    : super(retry: null, name: r'visitPlansProvider', dependencies: null, $allTransitiveDependencies: null, isAutoDispose: true);

  VisitPlansProvider call(String companyId) => VisitPlansProvider._(argument: companyId, from: this);

  @override
  String toString() => r'visitPlansProvider';
}

@ProviderFor(shopVisit)
final shopVisitProvider = ShopVisitFamily._();

final class ShopVisitProvider extends $FunctionalProvider<AsyncValue<ShopVisit?>, ShopVisit?, FutureOr<ShopVisit?>>
    with $FutureModifier<ShopVisit?>, $FutureProvider<ShopVisit?> {
  ShopVisitProvider._({required ShopVisitFamily super.from, required String super.argument})
    : super(retry: null, name: r'shopVisitProvider', isAutoDispose: true, dependencies: null, $allTransitiveDependencies: null);

  @override
  String debugGetCreateSourceHash() => _$shopVisitHash();

  @override
  String toString() {
    return r'shopVisitProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ShopVisit?> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<ShopVisit?> create(Ref ref) {
    final argument = this.argument as String;
    return shopVisit(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ShopVisitProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shopVisitHash() => r'798f64a5b0ab8d1cff3bb14860b87a8772d3e99d';

final class ShopVisitFamily extends $Family with $FunctionalFamilyOverride<FutureOr<ShopVisit?>, String> {
  ShopVisitFamily._()
    : super(retry: null, name: r'shopVisitProvider', dependencies: null, $allTransitiveDependencies: null, isAutoDispose: true);

  ShopVisitProvider call(String visitId) => ShopVisitProvider._(argument: visitId, from: this);

  @override
  String toString() => r'shopVisitProvider';
}

@ProviderFor(failedAttempts)
final failedAttemptsProvider = FailedAttemptsFamily._();

final class FailedAttemptsProvider
    extends $FunctionalProvider<AsyncValue<List<FailedAttempt>>, List<FailedAttempt>, FutureOr<List<FailedAttempt>>>
    with $FutureModifier<List<FailedAttempt>>, $FutureProvider<List<FailedAttempt>> {
  FailedAttemptsProvider._({required FailedAttemptsFamily super.from, required String super.argument})
    : super(
        retry: null,
        name: r'failedAttemptsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$failedAttemptsHash();

  @override
  String toString() {
    return r'failedAttemptsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<FailedAttempt>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<FailedAttempt>> create(Ref ref) {
    final argument = this.argument as String;
    return failedAttempts(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is FailedAttemptsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$failedAttemptsHash() => r'a96a65c73ec107d89abdb77342c664d0155aacb8';

final class FailedAttemptsFamily extends $Family with $FunctionalFamilyOverride<FutureOr<List<FailedAttempt>>, String> {
  FailedAttemptsFamily._()
    : super(
        retry: null,
        name: r'failedAttemptsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  FailedAttemptsProvider call(String taskId) => FailedAttemptsProvider._(argument: taskId, from: this);

  @override
  String toString() => r'failedAttemptsProvider';
}
