import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/api/api_client.dart';
import '../../auth/presentation/session_controller.dart';
import '../domain/service_status.dart';

part 'subscription_providers.g.dart';

/// The business's subscription row; null when there is none (a business not
/// hosted by the WholeFlow server) or it can't be read right now. Reloaded on
/// sign-in and with every refresh. Once access has ended the server refuses
/// this read too, and the session switches to the paused screen instead.
@Riverpod(keepAlive: true)
Future<ServiceStatus?> serviceStatus(Ref ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  try {
    final row = (await ref.watch(apiClientProvider).get('service-status'))['service_status'];
    return row is Map<String, dynamic> ? ServiceStatus.fromJson(row) : null;
  } catch (e) {
    AppFailure.from(e); // a 402 still pauses the app
    return null; // banners are optional: never break a screen over them
  }
}
