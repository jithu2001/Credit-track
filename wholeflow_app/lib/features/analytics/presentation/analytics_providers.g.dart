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
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
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
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(AnalyticsSortController)
final analyticsSortControllerProvider = AnalyticsSortControllerProvider._();

final class AnalyticsSortControllerProvider
    extends $NotifierProvider<AnalyticsSortController, AnalyticsSort> {
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
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AnalyticsSort>(value),
    );
  }
}

String _$analyticsSortControllerHash() =>
    r'4814d2633d953115a53044732aa59c1b76b8a46a';

abstract class _$AnalyticsSortController extends $Notifier<AnalyticsSort> {
  AnalyticsSort build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AnalyticsSort, AnalyticsSort>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AnalyticsSort, AnalyticsSort>,
              AnalyticsSort,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Payment figures of a company with the current credit days, worked out on
/// the server; fetched again when the credit days change.

@ProviderFor(paymentSummary)
final paymentSummaryProvider = PaymentSummaryFamily._();

/// Payment figures of a company with the current credit days, worked out on
/// the server; fetched again when the credit days change.

final class PaymentSummaryProvider
    extends
        $FunctionalProvider<
          AsyncValue<BusinessPaymentSummary>,
          BusinessPaymentSummary,
          FutureOr<BusinessPaymentSummary>
        >
    with
        $FutureModifier<BusinessPaymentSummary>,
        $FutureProvider<BusinessPaymentSummary> {
  /// Payment figures of a company with the current credit days, worked out on
  /// the server; fetched again when the credit days change.
  PaymentSummaryProvider._({
    required PaymentSummaryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'paymentSummaryProvider',
         isAutoDispose: false,
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
  $FutureProviderElement<BusinessPaymentSummary> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

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

String _$paymentSummaryHash() => r'c180e939e5a3c4d4af47ae4f5ee51cd3bad12068';

/// Payment figures of a company with the current credit days, worked out on
/// the server; fetched again when the credit days change.

final class PaymentSummaryFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<BusinessPaymentSummary>, String> {
  PaymentSummaryFamily._()
    : super(
        retry: null,
        name: r'paymentSummaryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Payment figures of a company with the current credit days, worked out on
  /// the server; fetched again when the credit days change.

  PaymentSummaryProvider call(String companyId) =>
      PaymentSummaryProvider._(argument: companyId, from: this);

  @override
  String toString() => r'paymentSummaryProvider';
}

/// Overdue 30 days ago with the same credit period, for the trend line.

@ProviderFor(overdueMonthAgo)
final overdueMonthAgoProvider = OverdueMonthAgoFamily._();

/// Overdue 30 days ago with the same credit period, for the trend line.

final class OverdueMonthAgoProvider
    extends $FunctionalProvider<AsyncValue<Money?>, Money?, FutureOr<Money?>>
    with $FutureModifier<Money?>, $FutureProvider<Money?> {
  /// Overdue 30 days ago with the same credit period, for the trend line.
  OverdueMonthAgoProvider._({
    required OverdueMonthAgoFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'overdueMonthAgoProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$overdueMonthAgoHash();

  @override
  String toString() {
    return r'overdueMonthAgoProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Money?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Money?> create(Ref ref) {
    final argument = this.argument as String;
    return overdueMonthAgo(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is OverdueMonthAgoProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$overdueMonthAgoHash() => r'f4692e3b73066ceea43223da99bb0f12f10246a4';

/// Overdue 30 days ago with the same credit period, for the trend line.

final class OverdueMonthAgoFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Money?>, String> {
  OverdueMonthAgoFamily._()
    : super(
        retry: null,
        name: r'overdueMonthAgoProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Overdue 30 days ago with the same credit period, for the trend line.

  OverdueMonthAgoProvider call(String companyId) =>
      OverdueMonthAgoProvider._(argument: companyId, from: this);

  @override
  String toString() => r'overdueMonthAgoProvider';
}

/// One shop's bills under FIFO (the shop's Payments view).

@ProviderFor(shopPayments)
final shopPaymentsProvider = ShopPaymentsFamily._();

/// One shop's bills under FIFO (the shop's Payments view).

final class ShopPaymentsProvider
    extends
        $FunctionalProvider<
          AsyncValue<ShopPayments>,
          ShopPayments,
          FutureOr<ShopPayments>
        >
    with $FutureModifier<ShopPayments>, $FutureProvider<ShopPayments> {
  /// One shop's bills under FIFO (the shop's Payments view).
  ShopPaymentsProvider._({
    required ShopPaymentsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'shopPaymentsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shopPaymentsHash();

  @override
  String toString() {
    return r'shopPaymentsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ShopPayments> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ShopPayments> create(Ref ref) {
    final argument = this.argument as String;
    return shopPayments(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ShopPaymentsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shopPaymentsHash() => r'fbd6005ee255e87dee433608fdf095538ddd4229';

/// One shop's bills under FIFO (the shop's Payments view).

final class ShopPaymentsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ShopPayments>, String> {
  ShopPaymentsFamily._()
    : super(
        retry: null,
        name: r'shopPaymentsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One shop's bills under FIFO (the shop's Payments view).

  ShopPaymentsProvider call(String shopId) =>
      ShopPaymentsProvider._(argument: shopId, from: this);

  @override
  String toString() => r'shopPaymentsProvider';
}
