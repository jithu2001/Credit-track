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
