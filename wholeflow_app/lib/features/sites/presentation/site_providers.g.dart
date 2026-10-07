// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'site_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Sites of a company the caller can see, A–Z.

@ProviderFor(companySites)
final companySitesProvider = CompanySitesFamily._();

/// Sites of a company the caller can see, A–Z.

final class CompanySitesProvider extends $FunctionalProvider<AsyncValue<List<Site>>, List<Site>, FutureOr<List<Site>>>
    with $FutureModifier<List<Site>>, $FutureProvider<List<Site>> {
  /// Sites of a company the caller can see, A–Z.
  CompanySitesProvider._({required CompanySitesFamily super.from, required String super.argument})
    : super(
        retry: null,
        name: r'companySitesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$companySitesHash();

  @override
  String toString() {
    return r'companySitesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<Site>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Site>> create(Ref ref) {
    final argument = this.argument as String;
    return companySites(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CompanySitesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$companySitesHash() => r'f7fb89280b170f00d451a393e97d7469bd24d416';

/// Sites of a company the caller can see, A–Z.

final class CompanySitesFamily extends $Family with $FunctionalFamilyOverride<FutureOr<List<Site>>, String> {
  CompanySitesFamily._()
    : super(
        retry: null,
        name: r'companySitesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Sites of a company the caller can see, A–Z.

  CompanySitesProvider call(String companyId) => CompanySitesProvider._(argument: companyId, from: this);

  @override
  String toString() => r'companySitesProvider';
}

/// Every visible site of the business (staff form: sites of each company).

@ProviderFor(allSites)
final allSitesProvider = AllSitesProvider._();

/// Every visible site of the business (staff form: sites of each company).

final class AllSitesProvider extends $FunctionalProvider<AsyncValue<List<Site>>, List<Site>, FutureOr<List<Site>>>
    with $FutureModifier<List<Site>>, $FutureProvider<List<Site>> {
  /// Every visible site of the business (staff form: sites of each company).
  AllSitesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'allSitesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$allSitesHash();

  @$internal
  @override
  $FutureProviderElement<List<Site>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Site>> create(Ref ref) {
    return allSites(ref);
  }
}

String _$allSitesHash() => r'c4d9cd1ad0f792587ff9f740e22b6028998aaf0f';

/// Which half of the owner's Sites tab shows. A view setting only.

@ProviderFor(SitesTabController)
final sitesTabControllerProvider = SitesTabControllerProvider._();

/// Which half of the owner's Sites tab shows. A view setting only.
final class SitesTabControllerProvider extends $NotifierProvider<SitesTabController, SitesTab> {
  /// Which half of the owner's Sites tab shows. A view setting only.
  SitesTabControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sitesTabControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sitesTabControllerHash();

  @$internal
  @override
  SitesTabController create() => SitesTabController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SitesTab value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<SitesTab>(value));
  }
}

String _$sitesTabControllerHash() => r'ea45f3a286894029ba33320c8eccfd03cb7a9b7b';

/// Which half of the owner's Sites tab shows. A view setting only.

abstract class _$SitesTabController extends $Notifier<SitesTab> {
  SitesTab build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SitesTab, SitesTab>;
    final element = ref.element as $ClassProviderElement<AnyNotifier<SitesTab, SitesTab>, SitesTab, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}

/// The period the Sites tab reports on. A view setting only: kept in memory.

@ProviderFor(ReportPeriodController)
final reportPeriodControllerProvider = ReportPeriodControllerProvider._();

/// The period the Sites tab reports on. A view setting only: kept in memory.
final class ReportPeriodControllerProvider extends $NotifierProvider<ReportPeriodController, ReportPeriod> {
  /// The period the Sites tab reports on. A view setting only: kept in memory.
  ReportPeriodControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reportPeriodControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reportPeriodControllerHash();

  @$internal
  @override
  ReportPeriodController create() => ReportPeriodController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReportPeriod value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<ReportPeriod>(value));
  }
}

String _$reportPeriodControllerHash() => r'72e1e08c7fa96ef89e4197d4fa243ed3f6902821';

/// The period the Sites tab reports on. A view setting only: kept in memory.

abstract class _$ReportPeriodController extends $Notifier<ReportPeriod> {
  ReportPeriod build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ReportPeriod, ReportPeriod>;
    final element = ref.element as $ClassProviderElement<AnyNotifier<ReportPeriod, ReportPeriod>, ReportPeriod, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}

/// Per-site figures for the chosen period.

@ProviderFor(siteReport)
final siteReportProvider = SiteReportFamily._();

/// Per-site figures for the chosen period.

final class SiteReportProvider
    extends $FunctionalProvider<AsyncValue<List<SiteReportRow>>, List<SiteReportRow>, FutureOr<List<SiteReportRow>>>
    with $FutureModifier<List<SiteReportRow>>, $FutureProvider<List<SiteReportRow>> {
  /// Per-site figures for the chosen period.
  SiteReportProvider._({required SiteReportFamily super.from, required String super.argument})
    : super(retry: null, name: r'siteReportProvider', isAutoDispose: true, dependencies: null, $allTransitiveDependencies: null);

  @override
  String debugGetCreateSourceHash() => _$siteReportHash();

  @override
  String toString() {
    return r'siteReportProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<SiteReportRow>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<SiteReportRow>> create(Ref ref) {
    final argument = this.argument as String;
    return siteReport(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SiteReportProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$siteReportHash() => r'6b83c5cfd5e0ad7d065049daa6a35e0f9c6d1faa';

/// Per-site figures for the chosen period.

final class SiteReportFamily extends $Family with $FunctionalFamilyOverride<FutureOr<List<SiteReportRow>>, String> {
  SiteReportFamily._()
    : super(retry: null, name: r'siteReportProvider', dependencies: null, $allTransitiveDependencies: null, isAutoDispose: true);

  /// Per-site figures for the chosen period.

  SiteReportProvider call(String companyId) => SiteReportProvider._(argument: companyId, from: this);

  @override
  String toString() => r'siteReportProvider';
}

@ProviderFor(siteShops)
final siteShopsProvider = SiteShopsFamily._();

final class SiteShopsProvider
    extends $FunctionalProvider<AsyncValue<List<ShopSummary>>, List<ShopSummary>, FutureOr<List<ShopSummary>>>
    with $FutureModifier<List<ShopSummary>>, $FutureProvider<List<ShopSummary>> {
  SiteShopsProvider._({required SiteShopsFamily super.from, required String super.argument})
    : super(retry: null, name: r'siteShopsProvider', isAutoDispose: true, dependencies: null, $allTransitiveDependencies: null);

  @override
  String debugGetCreateSourceHash() => _$siteShopsHash();

  @override
  String toString() {
    return r'siteShopsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<ShopSummary>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ShopSummary>> create(Ref ref) {
    final argument = this.argument as String;
    return siteShops(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SiteShopsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$siteShopsHash() => r'4b4f1c26e865a011ca264561bc45887bc9f26fd0';

final class SiteShopsFamily extends $Family with $FunctionalFamilyOverride<FutureOr<List<ShopSummary>>, String> {
  SiteShopsFamily._()
    : super(retry: null, name: r'siteShopsProvider', dependencies: null, $allTransitiveDependencies: null, isAutoDispose: true);

  SiteShopsProvider call(String siteId) => SiteShopsProvider._(argument: siteId, from: this);

  @override
  String toString() => r'siteShopsProvider';
}

/// All shops of a company with their current site, for the site editor.

@ProviderFor(companySiteShops)
final companySiteShopsProvider = CompanySiteShopsFamily._();

/// All shops of a company with their current site, for the site editor.

final class CompanySiteShopsProvider
    extends $FunctionalProvider<AsyncValue<List<SiteShop>>, List<SiteShop>, FutureOr<List<SiteShop>>>
    with $FutureModifier<List<SiteShop>>, $FutureProvider<List<SiteShop>> {
  /// All shops of a company with their current site, for the site editor.
  CompanySiteShopsProvider._({required CompanySiteShopsFamily super.from, required String super.argument})
    : super(
        retry: null,
        name: r'companySiteShopsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$companySiteShopsHash();

  @override
  String toString() {
    return r'companySiteShopsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<SiteShop>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<SiteShop>> create(Ref ref) {
    final argument = this.argument as String;
    return companySiteShops(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CompanySiteShopsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$companySiteShopsHash() => r'e2fa8891dc42e47aba9558b24aa74e4f2dfc2e90';

/// All shops of a company with their current site, for the site editor.

final class CompanySiteShopsFamily extends $Family with $FunctionalFamilyOverride<FutureOr<List<SiteShop>>, String> {
  CompanySiteShopsFamily._()
    : super(
        retry: null,
        name: r'companySiteShopsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// All shops of a company with their current site, for the site editor.

  CompanySiteShopsProvider call(String companyId) => CompanySiteShopsProvider._(argument: companyId, from: this);

  @override
  String toString() => r'companySiteShopsProvider';
}
