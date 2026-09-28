import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../phone.dart';
import 'states.dart';

/// A phone number with Call and (when addressable) WhatsApp buttons.
class PhoneTile extends StatelessWidget {
  const PhoneTile({super.key, required this.phone, this.fromAddress = false});

  final String phone;
  final bool fromAddress;

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showMessage(context, "Couldn't open ${uri.scheme == 'tel' ? 'the dialer' : 'WhatsApp'}.");
  }

  @override
  Widget build(BuildContext context) {
    final wa = whatsAppUri(phone);
    return ListTile(
      leading: const Icon(Icons.phone_outlined),
      title: Text(phone),
      subtitle: fromAddress ? const Text('Found in address') : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Call $phone',
            icon: const Icon(Icons.call_rounded),
            onPressed: () => _open(context, telUri(phone)),
          ),
          if (wa != null)
            IconButton(tooltip: 'WhatsApp $phone', icon: const Icon(Icons.chat_rounded), onPressed: () => _open(context, wa)),
        ],
      ),
    );
  }
}
