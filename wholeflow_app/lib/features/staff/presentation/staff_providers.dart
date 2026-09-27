import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/presentation/session_controller.dart';
import '../data/staff_repository.dart';
import '../domain/staff.dart';

part 'staff_providers.g.dart';

@riverpod
Future<List<StaffMember>> staffMembers(Ref ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null || !user.isOwner) return const [];
  return ref.watch(staffRepositoryProvider).members();
}

@riverpod
Future<StaffMember?> staffMember(Ref ref, String id) async {
  final all = await ref.watch(staffMembersProvider.future);
  for (final m in all) {
    if (m.id == id) return m;
  }
  return null;
}
