// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The Supabase client. Overridden in main() after Supabase.initialize and in tests.

@ProviderFor(supabase)
final supabaseProvider = SupabaseProvider._();

/// The Supabase client. Overridden in main() after Supabase.initialize and in tests.

final class SupabaseProvider extends $FunctionalProvider<SupabaseClient, SupabaseClient, SupabaseClient>
    with $Provider<SupabaseClient> {
  /// The Supabase client. Overridden in main() after Supabase.initialize and in tests.
  SupabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'supabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$supabaseHash();

  @$internal
  @override
  $ProviderElement<SupabaseClient> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  SupabaseClient create(Ref ref) {
    return supabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SupabaseClient value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<SupabaseClient>(value));
  }
}

String _$supabaseHash() => r'4806e68b35b539a9c7917d5d30465bb5984c4fb4';

/// Loaded in main() before runApp so reads are synchronous.

@ProviderFor(sharedPreferences)
final sharedPreferencesProvider = SharedPreferencesProvider._();

/// Loaded in main() before runApp so reads are synchronous.

final class SharedPreferencesProvider extends $FunctionalProvider<SharedPreferences, SharedPreferences, SharedPreferences>
    with $Provider<SharedPreferences> {
  /// Loaded in main() before runApp so reads are synchronous.
  SharedPreferencesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sharedPreferencesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sharedPreferencesHash();

  @$internal
  @override
  $ProviderElement<SharedPreferences> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  SharedPreferences create(Ref ref) {
    return sharedPreferences(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SharedPreferences value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<SharedPreferences>(value));
  }
}

String _$sharedPreferencesHash() => r'70ef90bd70df9f89260fca9b542d9f8d25d8e3cb';
