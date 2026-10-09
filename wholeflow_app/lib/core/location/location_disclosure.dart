import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'location_service.dart';

/// What the app tells the user before the phone's location permission prompt
/// (Google Play's prominent-disclosure rule): what is collected, when, and
/// who sees it.
enum LocationPurpose {
  checkIn(
    'Your location is used for check-in',
    'When you check in at a shop, WholeFlow reads your phone\'s GPS position (with its accuracy and the time) '
        'and sends it to your business owner, with the distance to the shop.\n\n'
        'Location is read only while the check-in screen is open. WholeFlow never tracks you in the '
        'background or when the app is closed.',
  ),
  pinShop(
    'Your location is used to pin the shop',
    'To place this shop\'s pin where you are standing, WholeFlow reads your phone\'s GPS position once and '
        'saves it as the shop\'s location for your business.\n\n'
        'Location is read only while this screen is open. WholeFlow never tracks you in the background.',
  );

  const LocationPurpose(this.title, this.body);

  final String title;
  final String body;
}

/// Shows the disclosure when the phone is about to ask for the location
/// permission; true when the app may go ahead (already allowed, or the user
/// chose Continue).
Future<bool> ensureLocationDisclosure(BuildContext context, LocationService service, LocationPurpose purpose) async {
  if (!await service.willAskPermission()) return true;
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      key: const Key('location-disclosure'),
      icon: Icon(Icons.location_on_outlined, color: context.colors.primary, size: 32),
      title: Text(purpose.title),
      content: SingleChildScrollView(child: Text(purpose.body)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
      ],
    ),
  );
  return ok == true;
}
