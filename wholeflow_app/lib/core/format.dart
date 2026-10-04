import 'package:intl/intl.dart';

final _date = DateFormat('d MMM yyyy');
final _dateTime = DateFormat('d MMM yyyy, h:mm a');

String formatDate(DateTime d) => _date.format(d);
String formatDateTime(DateTime d) => _dateTime.format(d.toLocal());

/// "just now", "4 min ago", "3 h ago", "2 days ago", then a date.
String timeAgo(DateTime then, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(then);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return 'on ${formatDate(then.toLocal())}';
}

/// "Rajakkad" for null/blank-safe display of derived areas.
String areaLabel(String? area) => (area == null || area.trim().isEmpty) ? 'No area' : area.trim();

/// "1 day", "3 days", "1 shop", "0 bills".
String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

final _qty = NumberFormat('#,##,##0.###', 'en_IN');

/// Stock quantity with Indian grouping and up to three decimals, e.g.
/// `1,250 Nos`, `12.5 Kg`. Quantities are for display only, so double is fine.
String formatQty(double qty, [String? unit]) {
  final text = _qty.format(qty);
  final u = unit?.trim() ?? '';
  return u.isEmpty ? text : '$text $u';
}

/// Parses a PostgREST `numeric` quantity (JSON number or string).
double parseQty(Object? value) => switch (value) {
  null => 0.0,
  final num v => v.toDouble(),
  _ => double.tryParse(value.toString()) ?? 0,
};

/// A `date` column (`2026-09-28`) as a local calendar date.
DateTime? parseDate(Object? value) => value == null ? null : DateTime.tryParse(value.toString());

/// `text[]` column as a list of non-blank strings.
List<String> parseStrings(Object? value) => [
  if (value is List)
    for (final v in value)
      if (v != null && v.toString().trim().isNotEmpty) v.toString().trim(),
];
