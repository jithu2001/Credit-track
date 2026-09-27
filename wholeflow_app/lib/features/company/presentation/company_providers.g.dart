// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'company_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Companies the signed-in user can see (RLS-filtered). Reloaded per user.

@ProviderFor(companies)
final companiesProvider = CompaniesProvider._();

/// Companies the signed-in user can see (RLS-filtered). Reloaded per user.

final class CompaniesProvider extends $FunctionalProvider<AsyncValue<List<Company>>, List<Company>, FutureOr<List<Company>>>
    with $FutureModifier<List<Company>>, $FutureProvider<List<Company>> {
  /// Companies the signed-in user can see (RLS-filtered). Reloaded per user.
  CompaniesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'companiesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$companiesHash();

  @$internal
  @override
  $FutureProviderElement<List<Company>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Company>> create(Ref ref) {
    return companies(ref);
  }
}

String _$companiesHash() => r'a1fef07d80fb17398a34e44ce24a97ddd48cd7e6';

/// The staff member's assignments keyed by company id; empty for owners.

@ProviderFor(myAccess)
final myAccessProvider = MyAccessProvider._();

/// The staff member's assignments keyed by company id; empty for owners.

final class MyAccessProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, CompanyAccess>>,
          Map<String, CompanyAccess>,
          FutureOr<Map<String, CompanyAccess>>
        >
    with $FutureModifier<Map<String, CompanyAccess>>, $FutureProvider<Map<String, CompanyAccess>> {
  /// The staff member's assignments keyed by company id; empty for owners.
  MyAccessProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myAccessProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myAccessHash();

  @$internal
  @override
  $FutureProviderElement<Map<String, CompanyAccess>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<String, CompanyAccess>> create(Ref ref) {
    return myAccess(ref);
  }
}

String _$myAccessHash() => r'37065d631f43c73f21ed9438720743ff773d45ba';

/// The remembered company choice (may point to a company no longer visible).

@ProviderFor(SelectedCompanyId)
final selectedCompanyIdProvider = SelectedCompanyIdProvider._();

/// The remembered company choice (may point to a company no longer visible).
final class SelectedCompanyIdProvider extends $NotifierProvider<SelectedCompanyId, String?> {
  /// The remembered company choice (may point to a company no longer visible).
  SelectedCompanyIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedCompanyIdProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedCompanyIdHash();

  @$internal
  @override
  SelectedCompanyId create() => SelectedCompanyId();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<String?>(value));
  }
}

String _$selectedCompanyIdHash() => r'cd0bceac2bb0a807b2b123c738b22d25b49572a2';

/// The remembered company choice (may point to a company no longer visible).

abstract class _$SelectedCompanyId extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element = ref.element as $ClassProviderElement<AnyNotifier<String?, String?>, String?, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}

/// The company every data screen is scoped to: the remembered one if still
/// visible, otherwise the first. Null when the user can see no company.

@ProviderFor(activeCompany)
final activeCompanyProvider = ActiveCompanyProvider._();

/// The company every data screen is scoped to: the remembered one if still
/// visible, otherwise the first. Null when the user can see no company.

final class ActiveCompanyProvider extends $FunctionalProvider<AsyncValue<Company?>, Company?, FutureOr<Company?>>
    with $FutureModifier<Company?>, $FutureProvider<Company?> {
  /// The company every data screen is scoped to: the remembered one if still
  /// visible, otherwise the first. Null when the user can see no company.
  ActiveCompanyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeCompanyProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeCompanyHash();

  @$internal
  @override
  $FutureProviderElement<Company?> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<Company?> create(Ref ref) {
    return activeCompany(ref);
  }
}

String _$activeCompanyHash() => r'9e947043c149c0e935705443e82c0ba9593e70b2';

/// Whether the Statement tab is shown for [companyId].

@ProviderFor(canViewTransactions)
final canViewTransactionsProvider = CanViewTransactionsFamily._();

/// Whether the Statement tab is shown for [companyId].

final class CanViewTransactionsProvider extends $FunctionalProvider<bool, bool, bool> with $Provider<bool> {
  /// Whether the Statement tab is shown for [companyId].
  CanViewTransactionsProvider._({required CanViewTransactionsFamily super.from, required String super.argument})
    : super(
        retry: null,
        name: r'canViewTransactionsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$canViewTransactionsHash();

  @override
  String toString() {
    return r'canViewTransactionsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    final argument = this.argument as String;
    return canViewTransactions(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<bool>(value));
  }

  @override
  bool operator ==(Object other) {
    return other is CanViewTransactionsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$canViewTransactionsHash() => r'd37750b6d402ef937fe065f649921150e991bbf2';

/// Whether the Statement tab is shown for [companyId].

final class CanViewTransactionsFamily extends $Family with $FunctionalFamilyOverride<bool, String> {
  CanViewTransactionsFamily._()
    : super(
        retry: null,
        name: r'canViewTransactionsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether the Statement tab is shown for [companyId].

  CanViewTransactionsProvider call(String companyId) => CanViewTransactionsProvider._(argument: companyId, from: this);

  @override
  String toString() => r'canViewTransactionsProvider';
}

/// Distinct shop areas of a company.

@ProviderFor(companyAreas)
final companyAreasProvider = CompanyAreasFamily._();

/// Distinct shop areas of a company.

final class CompanyAreasProvider extends $FunctionalProvider<AsyncValue<List<String>>, List<String>, FutureOr<List<String>>>
    with $FutureModifier<List<String>>, $FutureProvider<List<String>> {
  /// Distinct shop areas of a company.
  CompanyAreasProvider._({required CompanyAreasFamily super.from, required String super.argument})
    : super(
        retry: null,
        name: r'companyAreasProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$companyAreasHash();

  @override
  String toString() {
    return r'companyAreasProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<String>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<String>> create(Ref ref) {
    final argument = this.argument as String;
    return companyAreas(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CompanyAreasProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$companyAreasHash() => r'd013f248e4f0be6b2e4cc5f6ac1a2491edf9e7c2';

/// Distinct shop areas of a company.

final class CompanyAreasFamily extends $Family with $FunctionalFamilyOverride<FutureOr<List<String>>, String> {
  CompanyAreasFamily._()
    : super(
        retry: null,
        name: r'companyAreasProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Distinct shop areas of a company.

  CompanyAreasProvider call(String companyId) => CompanyAreasProvider._(argument: companyId, from: this);

  @override
  String toString() => r'companyAreasProvider';
}
