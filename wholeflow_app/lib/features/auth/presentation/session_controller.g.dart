// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's single source of truth for who is signed in.
///
/// A session only counts as signed in once the caller's `public.users` row is
/// loaded and active; otherwise the Supabase session is dropped.

@ProviderFor(SessionController)
final sessionControllerProvider = SessionControllerProvider._();

/// The app's single source of truth for who is signed in.
///
/// A session only counts as signed in once the caller's `public.users` row is
/// loaded and active; otherwise the Supabase session is dropped.
final class SessionControllerProvider extends $AsyncNotifierProvider<SessionController, Session> {
  /// The app's single source of truth for who is signed in.
  ///
  /// A session only counts as signed in once the caller's `public.users` row is
  /// loaded and active; otherwise the Supabase session is dropped.
  SessionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionControllerHash();

  @$internal
  @override
  SessionController create() => SessionController();
}

String _$sessionControllerHash() => r'20ac1dc8f02269d1b0e8c39e64390b0849d90012';

/// The app's single source of truth for who is signed in.
///
/// A session only counts as signed in once the caller's `public.users` row is
/// loaded and active; otherwise the Supabase session is dropped.

abstract class _$SessionController extends $AsyncNotifier<Session> {
  FutureOr<Session> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Session>, Session>;
    final element =
        ref.element as $ClassProviderElement<AnyNotifier<AsyncValue<Session>, Session>, AsyncValue<Session>, Object?, Object?>;
    return element.handleCreate(ref, build);
  }
}

/// The signed-in user; null while signed out (screens can rebuild for a frame
/// during sign-out before the router moves to the login screen).

@ProviderFor(currentUser)
final currentUserProvider = CurrentUserProvider._();

/// The signed-in user; null while signed out (screens can rebuild for a frame
/// during sign-out before the router moves to the login screen).

final class CurrentUserProvider extends $FunctionalProvider<AppUser?, AppUser?, AppUser?> with $Provider<AppUser?> {
  /// The signed-in user; null while signed out (screens can rebuild for a frame
  /// during sign-out before the router moves to the login screen).
  CurrentUserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentUserProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentUserHash();

  @$internal
  @override
  $ProviderElement<AppUser?> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  AppUser? create(Ref ref) {
    return currentUser(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppUser? value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<AppUser?>(value));
  }
}

String _$currentUserHash() => r'96206646a6ae187588bacbe9fb2795510f7990e4';
