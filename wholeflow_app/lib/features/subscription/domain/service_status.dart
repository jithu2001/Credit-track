/// How the business's WholeFlow subscription stands, as the apps show it.
/// Mirrors `public.access_state()` in the business database.
enum AccessState { active, renewalDue, grace, ended }

/// The business's one `service_status` row, written by the WholeFlow server.
class ServiceStatus {
  const ServiceStatus({
    required this.status,
    this.paidUntil,
    this.graceUntil,
    this.remindFrom,
    this.planName,
    this.message,
    this.contact,
  });

  factory ServiceStatus.fromJson(Map<String, dynamic> j) => ServiceStatus(
    status: (j['status'] as String?) ?? 'active',
    paidUntil: _date(j['paid_until']),
    graceUntil: _date(j['grace_until']),
    remindFrom: _date(j['remind_from']),
    planName: j['plan_name'] as String?,
    message: _text(j['message']),
    contact: _text(j['contact']),
  );

  /// 'active' | 'suspended' | 'closed'.
  final String status;
  final DateTime? paidUntil;
  final DateTime? graceUntil;
  final DateTime? remindFrom;
  final String? planName;
  final String? message;
  final String? contact;

  AccessState stateOn(DateTime today) {
    final t = DateTime.utc(today.year, today.month, today.day);
    if (status != 'active') return AccessState.ended;
    if (graceUntil != null && t.isAfter(graceUntil!)) return AccessState.ended;
    if (paidUntil != null && t.isAfter(paidUntil!)) return AccessState.grace;
    if (remindFrom != null && !t.isBefore(remindFrom!)) return AccessState.renewalDue;
    return AccessState.active;
  }

  static DateTime? _date(Object? v) {
    if (v is! String || v.length < 10) return null;
    final d = DateTime.tryParse(v.substring(0, 10));
    return d == null ? null : DateTime.utc(d.year, d.month, d.day);
  }

  static String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
}

/// Today by the business clock (India), as the server counts days.
DateTime businessToday([DateTime? now]) {
  final ist = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime.utc(ist.year, ist.month, ist.day);
}
