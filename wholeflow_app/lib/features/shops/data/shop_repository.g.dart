// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shop_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(shopRepository)
final shopRepositoryProvider = ShopRepositoryProvider._();

final class ShopRepositoryProvider extends $FunctionalProvider<ShopRepository, ShopRepository, ShopRepository>
    with $Provider<ShopRepository> {
  ShopRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shopRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shopRepositoryHash();

  @$internal
  @override
  $ProviderElement<ShopRepository> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  ShopRepository create(Ref ref) {
    return shopRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShopRepository value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<ShopRepository>(value));
  }
}

String _$shopRepositoryHash() => r'a6833ca6e2065f7c2e0c348c361609b732b35db2';
