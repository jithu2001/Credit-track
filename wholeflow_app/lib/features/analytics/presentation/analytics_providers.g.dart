// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'analytics_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The credit period filter. A view setting only: kept in memory, never saved.

@ProviderFor(CreditDays)
final creditDaysProvider = CreditDaysProvider._();

/// The credit period filter. A view setting only: kept in memory, never saved.
final class CreditDaysProvider extends $NotifierProvider<CreditDays, int> {
  /// The credit period filter. A view setting only: kept in memory, never saved.
  CreditDaysProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'creditDaysProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$creditDaysHash();

  @$internal
  @override
  CreditDays create() => CreditDays();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<int>(value));
  }
}

String _$creditDaysHash() => r'1ec36eda8f9de28e1441d94e64663aae42969e12';

/// The credit period filter. A view setting only: kept in memory, never saved.

abstract class _$CreditDays extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element = ref.element as $ClassProviderElement<AnyNotifier<int, int>, int, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(AnalyticsSortController)
final analyticsSortControllerProvider = AnalyticsSortControllerProvider._();

final class AnalyticsSortControllerProvider extends $NotifierProvider<AnalyticsSortController, AnalyticsSort> {
  AnalyticsSortControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'analyticsSortControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$analyticsSortControllerHash();

  @$internal
  @override
  AnalyticsSortController create() => AnalyticsSortController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AnalyticsSort value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<AnalyticsSort>(value));
  }
}

String _$analyticsSortControllerHash() => r'f27cd9dcec112165185fbd1f46627bdaeaaea865';

abstract class _$AnalyticsSortController extends $Notifier<AnalyticsSort> {
  AnalyticsSort build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AnalyticsSort, AnalyticsSort>;
    final element =
        ref.element as $ClassProviderElement<AnyNotifier<AnalyticsSort, AnalyticsSort>, AnalyticsSort, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}

/// Raw data for a company; kept while the app runs, reloaded on refresh.

@ProviderFor(analyticsData)
final analyticsDataProvider = AnalyticsDataFamily._();

/// Raw data for a company; kept while the app runs, reloaded on refresh.

final class AnalyticsDataProvider extends $FunctionalProvider<AsyncValue<AnalyticsData>, AnalyticsData, FutureOr<AnalyticsData>>
    with $FutureModifier<AnalyticsData>, $FutureProvider<AnalyticsData> {
  /// Raw data for a company; kept while the app runs, reloaded on refresh.
  AnalyticsDataProvider._({required AnalyticsDataFamily super.from, required String super.argument})
    : super(
        retry: null,
        name: r'analyticsDataProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$analyticsDataHash();

  @override
  String toString() {
    return r'analyticsDataProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AnalyticsData> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<AnalyticsData> create(Ref ref) {
    final argument = this.argument as String;
    return analyticsData(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AnalyticsDataProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$analyticsDataHash() => r'b714d1fc6f25ace6f10e8534ee12e64223b3d00d';

/// Raw data for a company; kept while the app runs, reloaded on refresh.

final class AnalyticsDataFamily extends $Family with $FunctionalFamilyOverride<FutureOr<AnalyticsData>, String> {
  AnalyticsDataFamily._()
    : super(
        retry: null,
        name: r'analyticsDataProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Raw data for a company; kept while the app runs, reloaded on refresh.

  AnalyticsDataProvider call(String companyId) => AnalyticsDataProvider._(argument: companyId, from: this);

  @override
  String toString() => r'analyticsDataProvider';
}

/// FIFO analysis with the current credit days. Recomputed on the device when
/// the filter changes; the data is not fetched again.

@ProviderFor(paymentSummary)
final paymentSummaryProvider = PaymentSummaryFamily._();

/// FIFO analysis with the current credit days. Recomputed on the device when
/// the filter changes; the data is not fetched again.

final class PaymentSummaryProvider
    extends $FunctionalProvider<AsyncValue<BusinessPaymentSummary>, BusinessPaymentSummary, FutureOr<BusinessPaymentSummary>>
    with $FutureModifier<BusinessPaymentSummary>, $FutureProvider<BusinessPaymentSummary> {
  /// FIFO analysis with the current credit days. Recomputed on the device when
  /// the filter changes; the data is not fetched again.
  PaymentSummaryProvider._({required PaymentSummaryFamily super.from, required String super.argument})
    : super(
        retry: null,
        name: r'paymentSummaryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$paymentSummaryHash();

  @override
  String toString() {
    return r'paymentSummaryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<BusinessPaymentSummary> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<BusinessPaymentSummary> create(Ref ref) {
    final argument = this.argument as String;
    return paymentSummary(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PaymentSummaryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$paymentSummaryHash() => r'402c4757a54ff1360499434f3a9b7780de93d0d6';

/// FIFO analysis with the current credit days. Recomputed on the device when
/// the filter changes; the data is not fetched again.

final class PaymentSummaryFamily extends $Family with $FunctionalFamilyOverride<FutureOr<BusinessPaymentSummary>, String> {
  PaymentSummaryFamily._()
    : super(
        retry: null,
        name: r'paymentSummaryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// FIFO analysis with the current credit days. Recomputed on the device when
  /// the filter changes; the data is not fetched again.

  PaymentSummaryProvider call(String companyId) => PaymentSummaryProvider._(argument: companyId, from: this);

  @override
  String toString() => r'paymentSummaryProvider';
}
