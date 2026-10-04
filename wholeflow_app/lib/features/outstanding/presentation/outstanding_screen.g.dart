// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outstanding_screen.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(outstandingReport)
final outstandingReportProvider = OutstandingReportFamily._();

final class OutstandingReportProvider
    extends
        $FunctionalProvider<
          AsyncValue<OutstandingReport>,
          OutstandingReport,
          FutureOr<OutstandingReport>
        >
    with
        $FutureModifier<OutstandingReport>,
        $FutureProvider<OutstandingReport> {
  OutstandingReportProvider._({
    required OutstandingReportFamily super.from,
    required Company super.argument,
  }) : super(
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
  $FutureProviderElement<OutstandingReport> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

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

String _$outstandingReportHash() => r'd246a36b7dfc3451cc1cad6c465a0c9062e6abfb';

final class OutstandingReportFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<OutstandingReport>, Company> {
  OutstandingReportFamily._()
    : super(
        retry: null,
        name: r'outstandingReportProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  OutstandingReportProvider call(Company company) =>
      OutstandingReportProvider._(argument: company, from: this);

  @override
  String toString() => r'outstandingReportProvider';
}

/// Which list the Outstanding screen shows. A view setting only: kept in memory.

@ProviderFor(OutstandingViewController)
final outstandingViewControllerProvider = OutstandingViewControllerProvider._();

/// Which list the Outstanding screen shows. A view setting only: kept in memory.
final class OutstandingViewControllerProvider
    extends $NotifierProvider<OutstandingViewController, OutstandingView> {
  /// Which list the Outstanding screen shows. A view setting only: kept in memory.
  OutstandingViewControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'outstandingViewControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$outstandingViewControllerHash();

  @$internal
  @override
  OutstandingViewController create() => OutstandingViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OutstandingView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OutstandingView>(value),
    );
  }
}

String _$outstandingViewControllerHash() =>
    r'36056b3f22440368c9c0df17137623d9051c71ed';

/// Which list the Outstanding screen shows. A view setting only: kept in memory.

abstract class _$OutstandingViewController extends $Notifier<OutstandingView> {
  OutstandingView build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<OutstandingView, OutstandingView>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<OutstandingView, OutstandingView>,
              OutstandingView,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Shops past the credit period; the period is shared with Analytics.

@ProviderFor(overdueReport)
final overdueReportProvider = OverdueReportFamily._();

/// Shops past the credit period; the period is shared with Analytics.

final class OverdueReportProvider
    extends
        $FunctionalProvider<
          AsyncValue<OverdueReport>,
          OverdueReport,
          FutureOr<OverdueReport>
        >
    with $FutureModifier<OverdueReport>, $FutureProvider<OverdueReport> {
  /// Shops past the credit period; the period is shared with Analytics.
  OverdueReportProvider._({
    required OverdueReportFamily super.from,
    required Company super.argument,
  }) : super(
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
  $FutureProviderElement<OverdueReport> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

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

String _$overdueReportHash() => r'41c8a58fe216554620a25367c9094493d222119b';

/// Shops past the credit period; the period is shared with Analytics.

final class OverdueReportFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<OverdueReport>, Company> {
  OverdueReportFamily._()
    : super(
        retry: null,
        name: r'overdueReportProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Shops past the credit period; the period is shared with Analytics.

  OverdueReportProvider call(Company company) =>
      OverdueReportProvider._(argument: company, from: this);

  @override
  String toString() => r'overdueReportProvider';
}
