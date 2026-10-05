// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shop_list_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The shop list's search/filter/sort; kept while the app runs.

@ProviderFor(ShopFilterController)
final shopFilterControllerProvider = ShopFilterControllerProvider._();

/// The shop list's search/filter/sort; kept while the app runs.
final class ShopFilterControllerProvider
    extends $NotifierProvider<ShopFilterController, ShopFilter> {
  /// The shop list's search/filter/sort; kept while the app runs.
  ShopFilterControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shopFilterControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shopFilterControllerHash();

  @$internal
  @override
  ShopFilterController create() => ShopFilterController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShopFilter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShopFilter>(value),
    );
  }
}

String _$shopFilterControllerHash() =>
    r'cade8acfbab6ef6d923dd369b33279381382942d';

/// The shop list's search/filter/sort; kept while the app runs.

abstract class _$ShopFilterController extends $Notifier<ShopFilter> {
  ShopFilter build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ShopFilter, ShopFilter>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ShopFilter, ShopFilter>,
              ShopFilter,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Which list the Shops tab shows; opens on Dues and keeps the last choice
/// while the app runs.

@ProviderFor(ShopsViewController)
final shopsViewControllerProvider = ShopsViewControllerProvider._();

/// Which list the Shops tab shows; opens on Dues and keeps the last choice
/// while the app runs.
final class ShopsViewControllerProvider
    extends $NotifierProvider<ShopsViewController, ShopsView> {
  /// Which list the Shops tab shows; opens on Dues and keeps the last choice
  /// while the app runs.
  ShopsViewControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shopsViewControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shopsViewControllerHash();

  @$internal
  @override
  ShopsViewController create() => ShopsViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShopsView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShopsView>(value),
    );
  }
}

String _$shopsViewControllerHash() =>
    r'd686a5116f343458a970e10da9d8bf8096baf806';

/// Which list the Shops tab shows; opens on Dues and keeps the last choice
/// while the app runs.

abstract class _$ShopsViewController extends $Notifier<ShopsView> {
  ShopsView build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ShopsView, ShopsView>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ShopsView, ShopsView>,
              ShopsView,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Infinite-scroll list of shops for a company with the current filter.

@ProviderFor(ShopList)
final shopListProvider = ShopListFamily._();

/// Infinite-scroll list of shops for a company with the current filter.
final class ShopListProvider
    extends $AsyncNotifierProvider<ShopList, ShopPage> {
  /// Infinite-scroll list of shops for a company with the current filter.
  ShopListProvider._({
    required ShopListFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'shopListProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shopListHash();

  @override
  String toString() {
    return r'shopListProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ShopList create() => ShopList();

  @override
  bool operator ==(Object other) {
    return other is ShopListProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shopListHash() => r'4642979cc270c21bc3a8d1954958b3c0ea4a7b7b';

/// Infinite-scroll list of shops for a company with the current filter.

final class ShopListFamily extends $Family
    with
        $ClassFamilyOverride<
          ShopList,
          AsyncValue<ShopPage>,
          ShopPage,
          FutureOr<ShopPage>,
          String
        > {
  ShopListFamily._()
    : super(
        retry: null,
        name: r'shopListProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Infinite-scroll list of shops for a company with the current filter.

  ShopListProvider call(String companyId) =>
      ShopListProvider._(argument: companyId, from: this);

  @override
  String toString() => r'shopListProvider';
}

/// Infinite-scroll list of shops for a company with the current filter.

abstract class _$ShopList extends $AsyncNotifier<ShopPage> {
  late final _$args = ref.$arg as String;
  String get companyId => _$args;

  FutureOr<ShopPage> build(String companyId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ShopPage>, ShopPage>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ShopPage>, ShopPage>,
              AsyncValue<ShopPage>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
