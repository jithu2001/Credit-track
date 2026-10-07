// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shop_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(shopRepository)
final shopRepositoryProvider = ShopRepositoryProvider._();

final class ShopRepositoryProvider
    extends $FunctionalProvider<ShopRepository, ShopRepository, ShopRepository>
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
  $ProviderElement<ShopRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ShopRepository create(Ref ref) {
    return shopRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShopRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShopRepository>(value),
    );
  }
}

String _$shopRepositoryHash() => r'357aa22c75da1e6b496eeb9ef7157b99ff9ce37e';
