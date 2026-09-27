// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'company_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(companyRepository)
final companyRepositoryProvider = CompanyRepositoryProvider._();

final class CompanyRepositoryProvider extends $FunctionalProvider<CompanyRepository, CompanyRepository, CompanyRepository>
    with $Provider<CompanyRepository> {
  CompanyRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'companyRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$companyRepositoryHash();

  @$internal
  @override
  $ProviderElement<CompanyRepository> $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  CompanyRepository create(Ref ref) {
    return companyRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CompanyRepository value) {
    return $ProviderOverride(origin: this, providerOverride: $SyncValueProvider<CompanyRepository>(value));
  }
}

String _$companyRepositoryHash() => r'60fb18c703490433647f1cb62bf1586e792643b0';
