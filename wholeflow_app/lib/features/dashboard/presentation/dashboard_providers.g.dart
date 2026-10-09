// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The whole dashboard, fetched in one call; the providers below are its parts.

@ProviderFor(dashboard)
final dashboardProvider = DashboardFamily._();

/// The whole dashboard, fetched in one call; the providers below are its parts.

final class DashboardProvider extends $FunctionalProvider<AsyncValue<Dashboard>, Dashboard, FutureOr<Dashboard>>
    with $FutureModifier<Dashboard>, $FutureProvider<Dashboard> {
  /// The whole dashboard, fetched in one call; the providers below are its parts.
  DashboardProvider._({required DashboardFamily super.from, required String super.argument})
    : super(retry: null, name: r'dashboardProvider', isAutoDispose: true, dependencies: null, $allTransitiveDependencies: null);

  @override
  String debugGetCreateSourceHash() => _$dashboardHash();

  @override
  String toString() {
    return r'dashboardProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Dashboard> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<Dashboard> create(Ref ref) {
    final argument = this.argument as String;
    return dashboard(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is DashboardProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$dashboardHash() => r'af18cd935dae508c0793741ca75a8e24f09f3e81';

/// The whole dashboard, fetched in one call; the providers below are its parts.

final class DashboardFamily extends $Family with $FunctionalFamilyOverride<FutureOr<Dashboard>, String> {
  DashboardFamily._()
    : super(retry: null, name: r'dashboardProvider', dependencies: null, $allTransitiveDependencies: null, isAutoDispose: true);

  /// The whole dashboard, fetched in one call; the providers below are its parts.

  DashboardProvider call(String companyId) => DashboardProvider._(argument: companyId, from: this);

  @override
  String toString() => r'dashboardProvider';
}

@ProviderFor(companySummary)
final companySummaryProvider = CompanySummaryFamily._();

final class CompanySummaryProvider
    extends $FunctionalProvider<AsyncValue<CompanySummary?>, CompanySummary?, FutureOr<CompanySummary?>>
    with $FutureModifier<CompanySummary?>, $FutureProvider<CompanySummary?> {
  CompanySummaryProvider._({required CompanySummaryFamily super.from, required String super.argument})
    : super(
        retry: null,
        name: r'companySummaryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$companySummaryHash();

  @override
  String toString() {
    return r'companySummaryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<CompanySummary?> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<CompanySummary?> create(Ref ref) {
    final argument = this.argument as String;
    return companySummary(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CompanySummaryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$companySummaryHash() => r'486c1435253dcfe5a83d8ba365cdfbb4b69cdfc4';

final class CompanySummaryFamily extends $Family with $FunctionalFamilyOverride<FutureOr<CompanySummary?>, String> {
  CompanySummaryFamily._()
    : super(
        retry: null,
        name: r'companySummaryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CompanySummaryProvider call(String companyId) => CompanySummaryProvider._(argument: companyId, from: this);

  @override
  String toString() => r'companySummaryProvider';
}

@ProviderFor(companySyncState)
final companySyncStateProvider = CompanySyncStateFamily._();

final class CompanySyncStateProvider extends $FunctionalProvider<AsyncValue<SyncState?>, SyncState?, FutureOr<SyncState?>>
    with $FutureModifier<SyncState?>, $FutureProvider<SyncState?> {
  CompanySyncStateProvider._({required CompanySyncStateFamily super.from, required String super.argument})
    : super(
        retry: null,
        name: r'companySyncStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$companySyncStateHash();

  @override
  String toString() {
    return r'companySyncStateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<SyncState?> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<SyncState?> create(Ref ref) {
    final argument = this.argument as String;
    return companySyncState(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CompanySyncStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$companySyncStateHash() => r'7911faec3dd03704fabc039deb61dbcb86fee44f';

final class CompanySyncStateFamily extends $Family with $FunctionalFamilyOverride<FutureOr<SyncState?>, String> {
  CompanySyncStateFamily._()
    : super(
        retry: null,
        name: r'companySyncStateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CompanySyncStateProvider call(String companyId) => CompanySyncStateProvider._(argument: companyId, from: this);

  @override
  String toString() => r'companySyncStateProvider';
}

/// Null for staff who may not see the company's transactions.

@ProviderFor(monthSales)
final monthSalesProvider = MonthSalesFamily._();

/// Null for staff who may not see the company's transactions.

final class MonthSalesProvider extends $FunctionalProvider<AsyncValue<MonthSales?>, MonthSales?, FutureOr<MonthSales?>>
    with $FutureModifier<MonthSales?>, $FutureProvider<MonthSales?> {
  /// Null for staff who may not see the company's transactions.
  MonthSalesProvider._({required MonthSalesFamily super.from, required String super.argument})
    : super(retry: null, name: r'monthSalesProvider', isAutoDispose: true, dependencies: null, $allTransitiveDependencies: null);

  @override
  String debugGetCreateSourceHash() => _$monthSalesHash();

  @override
  String toString() {
    return r'monthSalesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MonthSales?> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<MonthSales?> create(Ref ref) {
    final argument = this.argument as String;
    return monthSales(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MonthSalesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$monthSalesHash() => r'18bde73778c0d980bc4142f607bf0196acc4dbb5';

/// Null for staff who may not see the company's transactions.

final class MonthSalesFamily extends $Family with $FunctionalFamilyOverride<FutureOr<MonthSales?>, String> {
  MonthSalesFamily._()
    : super(retry: null, name: r'monthSalesProvider', dependencies: null, $allTransitiveDependencies: null, isAutoDispose: true);

  /// Null for staff who may not see the company's transactions.

  MonthSalesProvider call(String companyId) => MonthSalesProvider._(argument: companyId, from: this);

  @override
  String toString() => r'monthSalesProvider';
}

@ProviderFor(topDues)
final topDuesProvider = TopDuesFamily._();

final class TopDuesProvider
    extends $FunctionalProvider<AsyncValue<List<ShopSummary>>, List<ShopSummary>, FutureOr<List<ShopSummary>>>
    with $FutureModifier<List<ShopSummary>>, $FutureProvider<List<ShopSummary>> {
  TopDuesProvider._({required TopDuesFamily super.from, required String super.argument})
    : super(retry: null, name: r'topDuesProvider', isAutoDispose: true, dependencies: null, $allTransitiveDependencies: null);

  @override
  String debugGetCreateSourceHash() => _$topDuesHash();

  @override
  String toString() {
    return r'topDuesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<ShopSummary>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ShopSummary>> create(Ref ref) {
    final argument = this.argument as String;
    return topDues(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is TopDuesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$topDuesHash() => r'f354028bfc468b0bd95472cf7b32880ebb0bf4f2';

final class TopDuesFamily extends $Family with $FunctionalFamilyOverride<FutureOr<List<ShopSummary>>, String> {
  TopDuesFamily._()
    : super(retry: null, name: r'topDuesProvider', dependencies: null, $allTransitiveDependencies: null, isAutoDispose: true);

  TopDuesProvider call(String companyId) => TopDuesProvider._(argument: companyId, from: this);

  @override
  String toString() => r'topDuesProvider';
}
