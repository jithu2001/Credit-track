// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outstanding_views.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(outstandingReport)
final outstandingReportProvider = OutstandingReportFamily._();

final class OutstandingReportProvider
    extends $FunctionalProvider<AsyncValue<OutstandingReport>, OutstandingReport, FutureOr<OutstandingReport>>
    with $FutureModifier<OutstandingReport>, $FutureProvider<OutstandingReport> {
  OutstandingReportProvider._({required OutstandingReportFamily super.from, required Company super.argument})
    : super(
        retry: null,
        name: r'outstandingReportProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$outstandingReportHash();

  @override
  String toString() {
    return r'outstandingReportProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<OutstandingReport> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<OutstandingReport> create(Ref ref) {
    final argument = this.argument as Company;
    return outstandingReport(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is OutstandingReportProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$outstandingReportHash() => r'f403744f04be1ef02408487c8baa5e559f0be9b0';

final class OutstandingReportFamily extends $Family with $FunctionalFamilyOverride<FutureOr<OutstandingReport>, Company> {
  OutstandingReportFamily._()
    : super(
        retry: null,
        name: r'outstandingReportProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  OutstandingReportProvider call(Company company) => OutstandingReportProvider._(argument: company, from: this);

  @override
  String toString() => r'outstandingReportProvider';
}

@ProviderFor(overdueReport)
final overdueReportProvider = OverdueReportFamily._();

final class OverdueReportProvider extends $FunctionalProvider<AsyncValue<OverdueReport>, OverdueReport, FutureOr<OverdueReport>>
    with $FutureModifier<OverdueReport>, $FutureProvider<OverdueReport> {
  OverdueReportProvider._({required OverdueReportFamily super.from, required Company super.argument})
    : super(
        retry: null,
        name: r'overdueReportProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$overdueReportHash();

  @override
  String toString() {
    return r'overdueReportProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<OverdueReport> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<OverdueReport> create(Ref ref) {
    final argument = this.argument as Company;
    return overdueReport(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is OverdueReportProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$overdueReportHash() => r'ab7de396bdf197991058464661af9a338fac9c0b';

final class OverdueReportFamily extends $Family with $FunctionalFamilyOverride<FutureOr<OverdueReport>, Company> {
  OverdueReportFamily._()
    : super(
        retry: null,
        name: r'overdueReportProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  OverdueReportProvider call(Company company) => OverdueReportProvider._(argument: company, from: this);

  @override
  String toString() => r'overdueReportProvider';
}

/// How Shops → Overdue orders its shops. A view setting only: kept in memory.

@ProviderFor(OverdueSortController)
final overdueSortControllerProvider = OverdueSortControllerProvider._();

/// How Shops → Overdue orders its shops. A view setting only: kept in memory.
final class OverdueSortControllerProvider extends $NotifierProvider<OverdueSortController, OverdueSort> {
  /// How Shops → Overdue orders its shops. A view setting only: kept in memory.
  OverdueSortControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'overdueSortControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$overdueSortControllerHash();

  @$internal
  @override
  OverdueSortController create() => OverdueSortController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OverdueSort value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<OverdueSort>(value));
  }
}

String _$overdueSortControllerHash() => r'72eed1e63267063eda85f92143d486031b011ac0';

/// How Shops → Overdue orders its shops. A view setting only: kept in memory.

abstract class _$OverdueSortController extends $Notifier<OverdueSort> {
  OverdueSort build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<OverdueSort, OverdueSort>;
    final element = ref.element as $ClassProviderElement<AnyNotifier<OverdueSort, OverdueSort>, OverdueSort, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}
