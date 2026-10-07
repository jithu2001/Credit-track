import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Opens the system share sheet with [text] (WhatsApp, SMS, email…).
Future<void> shareText(String text, {String? subject}) => SharePlus.instance.share(ShareParams(text: text, subject: subject));

/// Opens the system share sheet with a PDF named `[fileStem].pdf`.
Future<void> sharePdf(Uint8List bytes, {required String fileStem, String? subject}) {
  final name = '$fileStem.pdf';
  return SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
      fileNameOverrides: [name],
      subject: subject,
    ),
  );
}
