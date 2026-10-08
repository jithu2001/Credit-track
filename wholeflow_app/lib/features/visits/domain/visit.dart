/// Where a planned shop visit stands (`v_visit_tasks.state`).
enum VisitState {
  verified('Checked in'),
  locationPending('Waiting for location'),
  unverified('Not verified'),
  pending('To visit'),
  missed('Missed');

  const VisitState(this.label);
  final String label;

  static VisitState parse(String? v) => switch (v) {
    'verified' => verified,
    'location_pending' => locationPending,
    'unverified' => unverified,
    'missed' => missed,
    _ => pending,
  };

  /// The staff member was at the shop (checked in, verified or waiting on the pin).
  bool get visited => this == verified || this == locationPending || this == unverified;
}

/// One shop to visit on one day, with its check-in if any (`v_visit_tasks`).
class VisitTask {
  const VisitTask({
    required this.taskId,
    required this.companyId,
    required this.staffId,
    required this.staffName,
    required this.shopId,
    required this.shopName,
    required this.siteName,
    required this.visitDate,
    required this.state,
    this.siteId,
    this.visitId,
    this.checkedInAt,
    this.distanceM,
    this.radiusM,
    this.accuracyM,
    this.note,
  });

  factory VisitTask.fromJson(Map<String, dynamic> json) => VisitTask(
    taskId: json['task_id'] as String,
    companyId: json['company_id'] as String,
    staffId: json['staff_id'] as String,
    staffName: (json['staff_name'] as String?) ?? '',
    shopId: json['shop_id'] as String,
    shopName: (json['shop_name'] as String?) ?? '',
    siteId: json['site_id'] as String?,
    siteName: (json['site_name'] as String?) ?? '',
    visitDate: DateTime.parse(json['visit_date'] as String),
    state: VisitState.parse(json['state'] as String?),
    visitId: json['visit_id'] as String?,
    checkedInAt: json['checked_in_at'] == null ? null : DateTime.parse(json['checked_in_at'] as String).toLocal(),
    distanceM: (json['distance_m'] as num?)?.toDouble(),
    radiusM: (json['radius_m'] as num?)?.toInt(),
    accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
    note: json['note'] as String?,
  );

  final String taskId;
  final String companyId;
  final String staffId;
  final String staffName;
  final String shopId;
  final String shopName;
  final String? siteId;
  final String siteName;
  final DateTime visitDate;
  final VisitState state;
  final String? visitId;
  final DateTime? checkedInAt;
  final double? distanceM;
  final int? radiusM;
  final double? accuracyM;
  final String? note;
}

/// How a day went for one staff member.
class DayProgress {
  const DayProgress(this.tasks);

  final List<VisitTask> tasks;

  int get total => tasks.length;
  int get visited => tasks.where((t) => t.state.visited).length;
  int get verified => tasks.where((t) => t.state == VisitState.verified).length;
  int get missed => tasks.where((t) => t.state == VisitState.missed).length;
  int get pending => tasks.where((t) => t.state == VisitState.pending).length;
}

/// A site planned for a staff member on one date, or every week on a weekday.
class VisitPlan {
  const VisitPlan({
    required this.id,
    required this.siteId,
    required this.staffId,
    required this.active,
    this.planDate,
    this.weekday,
    this.startsOn,
    this.endsOn,
    this.siteName,
    this.staffName,
  });

  factory VisitPlan.fromJson(Map<String, dynamic> json) {
    DateTime? day(Object? v) => v == null ? null : DateTime.parse(v as String);
    return VisitPlan(
      id: json['id'] as String,
      siteId: json['site_id'] as String,
      staffId: json['staff_id'] as String,
      active: (json['active'] as bool?) ?? true,
      planDate: day(json['plan_date']),
      weekday: (json['weekday'] as num?)?.toInt(),
      startsOn: day(json['starts_on']),
      endsOn: day(json['ends_on']),
      siteName: (json['sites'] as Map?)?['name'] as String?,
      staffName: (json['users'] as Map?)?['name'] as String?,
    );
  }

  final String id;
  final String siteId;
  final String staffId;
  final bool active;
  final DateTime? planDate;

  /// 1 = Monday … 7 = Sunday.
  final int? weekday;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final String? siteName;
  final String? staffName;

  bool get weekly => weekday != null;
}

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// The check-in record behind a visited task (`shop_visits`).
class ShopVisit {
  const ShopVisit({
    required this.id,
    required this.checkedInAt,
    required this.deviceLat,
    required this.deviceLng,
    required this.accuracyM,
    required this.status,
    this.shopLat,
    this.shopLng,
    this.radiusM,
    this.distanceM,
    this.note,
  });

  factory ShopVisit.fromJson(Map<String, dynamic> json) => ShopVisit(
    id: json['id'] as String,
    checkedInAt: DateTime.parse(json['checked_in_at'] as String).toLocal(),
    deviceLat: (json['device_lat'] as num).toDouble(),
    deviceLng: (json['device_lng'] as num).toDouble(),
    accuracyM: (json['accuracy_m'] as num).toDouble(),
    status: VisitState.parse(json['status'] as String?),
    shopLat: (json['shop_lat'] as num?)?.toDouble(),
    shopLng: (json['shop_lng'] as num?)?.toDouble(),
    radiusM: (json['radius_m'] as num?)?.toInt(),
    distanceM: (json['distance_m'] as num?)?.toDouble(),
    note: json['note'] as String?,
  );

  final String id;
  final DateTime checkedInAt;
  final double deviceLat;
  final double deviceLng;
  final double accuracyM;
  final VisitState status;
  final double? shopLat;
  final double? shopLng;
  final int? radiusM;
  final double? distanceM;
  final String? note;
}

/// A check-in the server refused (owners only).
class FailedAttempt {
  const FailedAttempt({required this.at, required this.reason, this.distanceM, this.radiusM, this.accuracyM});

  factory FailedAttempt.fromJson(Map<String, dynamic> json) => FailedAttempt(
    at: DateTime.parse(json['attempted_at'] as String).toLocal(),
    reason: json['reason'] as String,
    distanceM: (json['distance_m'] as num?)?.toDouble(),
    radiusM: (json['radius_m'] as num?)?.toInt(),
    accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
  );

  final DateTime at;
  final String reason;
  final double? distanceM;
  final int? radiusM;
  final double? accuracyM;

  String get label => checkInRejection(reason, distanceM: distanceM, radiusM: radiusM, accuracyM: accuracyM);
}

/// Plain words for why a check-in was refused.
String checkInRejection(String reason, {double? distanceM, int? radiusM, double? accuracyM}) => switch (reason) {
  'out_of_range' =>
    distanceM != null && radiusM != null ? '${distanceM.round()} m from the shop (allowed $radiusM m)' : 'Too far from the shop',
  'poor_accuracy' => accuracyM != null ? 'GPS too rough (±${accuracyM.round()} m, needs 50 m)' : 'GPS too rough',
  'mock_location' => 'Fake location app detected',
  'developer_options' => 'Developer options are on',
  _ => 'Refused',
};

/// What `check_in()` answered.
class CheckInResult {
  const CheckInResult({required this.result, this.reason, this.distanceM, this.radiusM});

  factory CheckInResult.fromJson(Map<String, dynamic> json) => CheckInResult(
    result: json['result'] as String,
    reason: json['reason'] as String?,
    distanceM: (json['distance_m'] as num?)?.toDouble(),
    radiusM: (json['radius_m'] as num?)?.toInt(),
  );

  /// "verified", "location_pending" or "rejected".
  final String result;
  final String? reason;
  final double? distanceM;
  final int? radiusM;

  bool get accepted => result != 'rejected';
}
