// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'overdue_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(overdueRepository)
final overdueRepositoryProvider = OverdueRepositoryProvider._();

final class OverdueRepositoryProvider extends $FunctionalProvider<OverdueRepository, OverdueRepository, OverdueRepository>
    with $Provider<OverdueRepository> {
  OverdueRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'overdueRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$overdueRepositoryHash();

  @$internal
  @override
  $ProviderElement<OverdueRepository> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  OverdueRepository create(Ref ref) {
    return overdueRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OverdueRepository value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<OverdueRepository>(value));
  }
}

String _$overdueRepositoryHash() => r'0f433a5ce55b533aef2ac14279407ca798ef044e';
