// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'staff_router.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(staffRouter)
final staffRouterProvider = StaffRouterProvider._();

final class StaffRouterProvider extends $FunctionalProvider<GoRouter, GoRouter, GoRouter> with $Provider<GoRouter> {
  StaffRouterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'staffRouterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$staffRouterHash();

  @$internal
  @override
  $ProviderElement<GoRouter> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  GoRouter create(Ref ref) {
    return staffRouter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GoRouter value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<GoRouter>(value));
  }
}

String _$staffRouterHash() => r'ea65d22709bf8c5f0a0836f574937ee34a71448f';
