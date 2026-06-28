/// `check_in` / `check_out` — mirrors `AttendanceRecord::TYPE_*` on the backend.
enum AttendanceType {
  checkIn,
  checkOut;

  static AttendanceType fromString(String? raw) =>
      raw == 'check_out' ? AttendanceType.checkOut : AttendanceType.checkIn;

  String get apiValue => switch (this) {
    AttendanceType.checkIn => 'check_in',
    AttendanceType.checkOut => 'check_out',
  };

  String get arabicLabel => switch (this) {
    AttendanceType.checkIn => 'حضور',
    AttendanceType.checkOut => 'انصراف',
  };

  /// The action that logically follows this one — used to compute the
  /// next check-in/out button label from the user's current status.
  AttendanceType get opposite =>
      this == AttendanceType.checkIn
          ? AttendanceType.checkOut
          : AttendanceType.checkIn;
}

/// A synced attendance record as returned by the backend
/// (`/attendance/record`, `/attendance/sync`, `/attendance/my-records`).
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.userId,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    required this.createdAt,
    this.selfiePath,
    this.selfieUrl,
    this.status,
    this.workHours,
  });

  final int id;
  final int userId;
  final AttendanceType type;
  final double latitude;
  final double longitude;
  final DateTime recordedAt;
  final DateTime createdAt;

  /// Disk-relative path on the public disk, e.g.
  /// `attendance-selfies/{user_id}/{Y-m-d}/{uuid}.{ext}`.
  final String? selfiePath;

  /// Ready-to-use, web-reachable URL — auto-appended by the backend to
  /// every JSON representation of an [AttendanceRecord].
  final String? selfieUrl;

  /// Server-persisted status. Only `missing_checkout` reaches the mobile
  /// app — set on a CHECK-IN row when the employee never checked out and
  /// the day was auto-closed at 22:00. `null` for a normal record.
  final String? status;

  /// Worked duration in decimal hours, stored on the CHECK-OUT row only —
  /// `null` on check-ins (and on checkouts the server couldn't pair).
  final double? workHours;

  /// True on a check-in the employee forgot to close — the day is
  /// incomplete and must NOT be shown as a full day worked.
  bool get isMissingCheckout => status == 'missing_checkout';

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) =>
      AttendanceRecord(
        id: (json['id'] as num).toInt(),
        userId: (json['user_id'] as num).toInt(),
        type: AttendanceType.fromString(json['type'] as String?),
        latitude: double.tryParse(json['latitude'].toString()) ?? 0,
        longitude: double.tryParse(json['longitude'].toString()) ?? 0,
        recordedAt: _parseDate(json['recorded_at']) ?? DateTime.now(),
        createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
        selfiePath: json['selfie_path'] as String?,
        selfieUrl: json['selfie_url'] as String?,
        status: json['status'] as String?,
        workHours: _parseDouble(json['work_hours']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'type': type.apiValue,
    'latitude': latitude,
    'longitude': longitude,
    'recorded_at': recordedAt.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'selfie_path': selfiePath,
    'selfie_url': selfieUrl,
    'status': status,
    'work_hours': workHours,
  };
}

/// Formats decimal [hours] (e.g. `8.5`) as a compact Arabic duration —
/// `"8 س 30 د"` (8h 30m). Used to display a checkout row's `work_hours`.
String formatWorkHours(double hours) {
  final totalMinutes = (hours * 60).round();
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h <= 0) return '$m د';
  if (m == 0) return '$h س';
  return '$h س $m د';
}

/// A page of attendance records with pagination metadata
/// (`GET /attendance/my-records`).
class AttendanceRecordsPage {
  const AttendanceRecordsPage({
    required this.records,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  final List<AttendanceRecord> records;
  final int currentPage;
  final int lastPage;
  final int total;

  bool get hasMore => currentPage < lastPage;

  factory AttendanceRecordsPage.fromJson(Map<String, dynamic> json) {
    final paginator = json['records'] as Map<String, dynamic>;
    return AttendanceRecordsPage(
      records: ((paginator['data'] as List?) ?? [])
          .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentPage: (paginator['current_page'] as num?)?.toInt() ?? 1,
      lastPage: (paginator['last_page'] as num?)?.toInt() ?? 1,
      total: (paginator['total'] as num?)?.toInt() ?? 0,
    );
  }
}

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toLocal();
}

double? _parseDouble(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString());
}
