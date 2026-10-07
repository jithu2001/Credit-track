// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'business_connection.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The connection the running app uses. Overridden in bootstrap.

@ProviderFor(businessConnection)
final businessConnectionProvider = BusinessConnectionProvider._();

/// The connection the running app uses. Overridden in bootstrap.

final class BusinessConnectionProvider
    extends
        $FunctionalProvider<
          BusinessConnection,
          BusinessConnection,
          BusinessConnection
        >
    with $Provider<BusinessConnection> {
  /// The connection the running app uses. Overridden in bootstrap.
  BusinessConnectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'businessConnectionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$businessConnectionHash();

  @$internal
  @override
  $ProviderElement<BusinessConnection> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BusinessConnection create(Ref ref) {
    return businessConnection(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BusinessConnection value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BusinessConnection>(value),
    );
  }
}

String _$businessConnectionHash() =>
    r'6524758e6bb3233644eb354754a087a4fe0c488d';

/// Closes the current business and shows the connect screen. Overridden in
/// bootstrap; a no-op in tests.

@ProviderFor(switchBusiness)
final switchBusinessProvider = SwitchBusinessProvider._();

/// Closes the current business and shows the connect screen. Overridden in
/// bootstrap; a no-op in tests.

final class SwitchBusinessProvider
    extends
        $FunctionalProvider<
          Future<void> Function(),
          Future<void> Function(),
          Future<void> Function()
        >
    with $Provider<Future<void> Function()> {
  /// Closes the current business and shows the connect screen. Overridden in
  /// bootstrap; a no-op in tests.
  SwitchBusinessProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'switchBusinessProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$switchBusinessHash();

  @$internal
  @override
  $ProviderElement<Future<void> Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Future<void> Function() create(Ref ref) {
    return switchBusiness(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Future<void> Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Future<void> Function()>(value),
    );
  }
}

String _$switchBusinessHash() => r'9c7162e8f01ddbc4ca54ec1c3aa3710509f4f94b';
