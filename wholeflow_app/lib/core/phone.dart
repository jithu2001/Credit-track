/// Digits of an Indian phone number in international form (`919876543210`),
/// or null when it doesn't look like a phone number.
String? toInternationalIndian(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.length == 11 && digits.startsWith('0')) digits = digits.substring(1);
  if (digits.length == 10) return '91$digits';
  if (digits.length == 12 && digits.startsWith('91')) return digits;
  return null;
}

Uri telUri(String raw) {
  final intl = toInternationalIndian(raw);
  return Uri(scheme: 'tel', path: intl != null ? '+$intl' : raw.replaceAll(RegExp(r'[^\d+]'), ''));
}

/// wa.me link, or null for numbers WhatsApp can't address (e.g. landlines without code).
Uri? whatsAppUri(String raw) {
  final intl = toInternationalIndian(raw);
  return intl == null ? null : Uri.parse('https://wa.me/$intl');
}
