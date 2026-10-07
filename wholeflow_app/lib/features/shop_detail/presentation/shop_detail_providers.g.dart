// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shop_detail_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(shopDetail)
final shopDetailProvider = ShopDetailFamily._();

final class ShopDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<ShopDetail>,
          ShopDetail,
          FutureOr<ShopDetail>
        >
    with $FutureModifier<ShopDetail>, $FutureProvider<ShopDetail> {
  ShopDetailProvider._({
    required ShopDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'shopDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shopDetailHash();

  @override
  String toString() {
    return r'shopDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ShopDetail> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<ShopDetail> create(Ref ref) {
    final argument = this.argument as String;
    return shopDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ShopDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shopDetailHash() => r'fb772cac94d481130ae2c02139fcb1432c37d10a';

final class ShopDetailFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ShopDetail>, String> {
  ShopDetailFamily._()
    : super(
        retry: null,
        name: r'shopDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ShopDetailProvider call(String shopId) =>
      ShopDetailProvider._(argument: shopId, from: this);

  @override
  String toString() => r'shopDetailProvider';
}

@ProviderFor(shopStatement)
final shopStatementProvider = ShopStatementFamily._();

final class ShopStatementProvider
    extends
        $FunctionalProvider<
          AsyncValue<Statement>,
          Statement,
          FutureOr<Statement>
        >
    with $FutureModifier<Statement>, $FutureProvider<Statement> {
  ShopStatementProvider._({
    required ShopStatementFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'shopStatementProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shopStatementHash();

  @override
  String toString() {
    return r'shopStatementProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Statement> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Statement> create(Ref ref) {
    final argument = this.argument as String;
    return shopStatement(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ShopStatementProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shopStatementHash() => r'4dccc0dd3b92f5eeafa01e32aa59e48bd1cbcf22';

final class ShopStatementFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Statement>, String> {
  ShopStatementFamily._()
    : super(
        retry: null,
        name: r'shopStatementProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ShopStatementProvider call(String shopId) =>
      ShopStatementProvider._(argument: shopId, from: this);

  @override
  String toString() => r'shopStatementProvider';
}
