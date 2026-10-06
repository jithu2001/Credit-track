// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subscription_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The business's subscription row; null when there is none (a business not
/// hosted by the WholeFlow server) or it can't be read right now. Reloaded on
/// sign-in and with every refresh. Once access has ended the server refuses
/// this read too, and the session switches to the paused screen instead.

@ProviderFor(serviceStatus)
final serviceStatusProvider = ServiceStatusProvider._();

/// The business's subscription row; null when there is none (a business not
/// hosted by the WholeFlow server) or it can't be read right now. Reloaded on
/// sign-in and with every refresh. Once access has ended the server refuses
/// this read too, and the session switches to the paused screen instead.

final class ServiceStatusProvider
    extends $FunctionalProvider<AsyncValue<ServiceStatus?>, ServiceStatus?, FutureOr<ServiceStatus?>>
    with $FutureModifier<ServiceStatus?>, $FutureProvider<ServiceStatus?> {
  /// The business's subscription row; null when there is none (a business not
  /// hosted by the WholeFlow server) or it can't be read right now. Reloaded on
  /// sign-in and with every refresh. Once access has ended the server refuses
  /// this read too, and the session switches to the paused screen instead.
  ServiceStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'serviceStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$serviceStatusHash();

  @$internal
  @override
  $FutureProviderElement<ServiceStatus?> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<ServiceStatus?> create(Ref ref) {
    return serviceStatus(ref);
  }
}

String _$serviceStatusHash() => r'16ff4d050c80de135282594ec9be2c7c844974e4';
