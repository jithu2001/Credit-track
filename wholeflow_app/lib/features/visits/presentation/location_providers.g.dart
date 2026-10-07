// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A shop's pin, or null when it has none.

@ProviderFor(shopLocation)
final shopLocationProvider = ShopLocationFamily._();

/// A shop's pin, or null when it has none.

final class ShopLocationProvider extends $FunctionalProvider<AsyncValue<ShopLocation?>, ShopLocation?, FutureOr<ShopLocation?>>
    with $FutureModifier<ShopLocation?>, $FutureProvider<ShopLocation?> {
  /// A shop's pin, or null when it has none.
  ShopLocationProvider._({required ShopLocationFamily super.from, required String super.argument})
    : super(
        retry: null,
        name: r'shopLocationProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shopLocationHash();

  @override
  String toString() {
    return r'shopLocationProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ShopLocation?> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<ShopLocation?> create(Ref ref) {
    final argument = this.argument as String;
    return shopLocation(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ShopLocationProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shopLocationHash() => r'4e621c0593ccf482a3009e64d52146b3efd8f306';

/// A shop's pin, or null when it has none.

final class ShopLocationFamily extends $Family with $FunctionalFamilyOverride<FutureOr<ShopLocation?>, String> {
  ShopLocationFamily._()
    : super(
        retry: null,
        name: r'shopLocationProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A shop's pin, or null when it has none.

  ShopLocationProvider call(String shopId) => ShopLocationProvider._(argument: shopId, from: this);

  @override
  String toString() => r'shopLocationProvider';
}

/// Staff suggestions waiting for the owner.

@ProviderFor(pendingSuggestions)
final pendingSuggestionsProvider = PendingSuggestionsProvider._();

/// Staff suggestions waiting for the owner.

final class PendingSuggestionsProvider
    extends
        $FunctionalProvider<AsyncValue<List<LocationSuggestion>>, List<LocationSuggestion>, FutureOr<List<LocationSuggestion>>>
    with $FutureModifier<List<LocationSuggestion>>, $FutureProvider<List<LocationSuggestion>> {
  /// Staff suggestions waiting for the owner.
  PendingSuggestionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pendingSuggestionsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pendingSuggestionsHash();

  @$internal
  @override
  $FutureProviderElement<List<LocationSuggestion>> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<LocationSuggestion>> create(Ref ref) {
    return pendingSuggestions(ref);
  }
}

String _$pendingSuggestionsHash() => r'2c4cbe23b25b248248545f6ae2ad5faad09d16a8';
