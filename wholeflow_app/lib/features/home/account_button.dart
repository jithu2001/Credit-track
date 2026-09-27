import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/states.dart';
import '../auth/presentation/session_controller.dart';

/// App-bar avatar that opens Settings (profile, theme, password, sign out).
class AccountButton extends ConsumerWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final initial = (user?.displayName.characters.firstOrNull ?? '?').toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton(
        tooltip: 'Account and settings',
        onPressed: () {
          dismissKeyboard();
          context.push('/settings');
        },
        icon: CircleAvatar(radius: 16, child: Text(initial)),
      ),
    );
  }
}
