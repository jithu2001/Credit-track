// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

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

String _$companySummaryHash() => r'6cbfa8c3ffe1359ae972c672b4cd5d5edbe263b8';

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

String _$companySyncStateHash() => r'ad29fdf89e6911a91c3dcef3ca3335da1d8eaa0e';

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

String _$topDuesHash() => r'1b35d88793d9e8dbe8f7cc27e02807782a480f0b';

final class TopDuesFamily extends $Family with $FunctionalFamilyOverride<FutureOr<List<ShopSummary>>, String> {
  TopDuesFamily._()
    : super(retry: null, name: r'topDuesProvider', dependencies: null, $allTransitiveDependencies: null, isAutoDispose: true);

  TopDuesProvider call(String companyId) => TopDuesProvider._(argument: companyId, from: this);

  @override
  String toString() => r'topDuesProvider';
}
