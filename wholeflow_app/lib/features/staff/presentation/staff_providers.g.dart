// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'staff_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(staffMembers)
final staffMembersProvider = StaffMembersProvider._();

final class StaffMembersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<StaffMember>>,
          List<StaffMember>,
          FutureOr<List<StaffMember>>
        >
    with
        $FutureModifier<List<StaffMember>>,
        $FutureProvider<List<StaffMember>> {
  StaffMembersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'staffMembersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$staffMembersHash();

  @$internal
  @override
  $FutureProviderElement<List<StaffMember>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<StaffMember>> create(Ref ref) {
    return staffMembers(ref);
  }
}

String _$staffMembersHash() => r'75b9c68937dc8df60989930cef192d38a24585ce';

@ProviderFor(staffMember)
final staffMemberProvider = StaffMemberFamily._();

final class StaffMemberProvider
    extends
        $FunctionalProvider<
          AsyncValue<StaffMember?>,
          StaffMember?,
          FutureOr<StaffMember?>
        >
    with $FutureModifier<StaffMember?>, $FutureProvider<StaffMember?> {
  StaffMemberProvider._({
    required StaffMemberFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'staffMemberProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$staffMemberHash();

  @override
  String toString() {
    return r'staffMemberProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<StaffMember?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<StaffMember?> create(Ref ref) {
    final argument = this.argument as String;
    return staffMember(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is StaffMemberProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$staffMemberHash() => r'7a102b6cc993ebf472d8565f367cda0c372e892b';

final class StaffMemberFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<StaffMember?>, String> {
  StaffMemberFamily._()
    : super(
        retry: null,
        name: r'staffMemberProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  StaffMemberProvider call(String id) =>
      StaffMemberProvider._(argument: id, from: this);

  @override
  String toString() => r'staffMemberProvider';
}
