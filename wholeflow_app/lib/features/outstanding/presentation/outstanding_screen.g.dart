// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outstanding_screen.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(outstandingReport)
final outstandingReportProvider = OutstandingReportFamily._();

final class OutstandingReportProvider
    extends $FunctionalProvider<AsyncValue<OutstandingReport>, OutstandingReport, FutureOr<OutstandingReport>>
    with $FutureModifier<OutstandingReport>, $FutureProvider<OutstandingReport> {
  OutstandingReportProvider._({required OutstandingReportFamily super.from, required Company super.argument})
    : super(
        retry: null,
        name: r'outstandingReportProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$outstandingReportHash();

  @override
  String toString() {
    return r'outstandingReportProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<OutstandingReport> $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<OutstandingReport> create(Ref ref) {
    final argument = this.argument as Company;
    return outstandingReport(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is OutstandingReportProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$outstandingReportHash() => r'd246a36b7dfc3451cc1cad6c465a0c9062e6abfb';

final class OutstandingReportFamily extends $Family with $FunctionalFamilyOverride<FutureOr<OutstandingReport>, Company> {
  OutstandingReportFamily._()
    : super(
        retry: null,
        name: r'outstandingReportProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  OutstandingReportProvider call(Company company) => OutstandingReportProvider._(argument: company, from: this);

  @override
  String toString() => r'outstandingReportProvider';
}
