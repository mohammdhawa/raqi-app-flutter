import 'attendance_record.dart';

/// Sync status of a [PendingAttendanceRecord] in the local offline queue.
enum AttendanceSyncStatus {
  pending,
  synced,
  failed;

  static AttendanceSyncStatus fromString(String? raw) => switch (raw) {
    'synced' => AttendanceSyncStatus.synced,
    'failed' => AttendanceSyncStatus.failed,
    _ => AttendanceSyncStatus.pending,
  };
}

/// A check-in/out captured on this device, queued locally until it's
/// confirmed by the backend. Stored in SQLite (see `AttendanceLocalDb`)
/// so it survives app restarts and offline periods.
class PendingAttendanceRecord {
  const PendingAttendanceRecord({
    this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.selfiePath,
    required this.recordedAt,
    this.status = AttendanceSyncStatus.pending,
    this.errorMessage,
  });

  /// Local SQLite row id — null until first inserted.
  final int? id;

  final AttendanceType type;
  final double latitude;
  final double longitude;

  /// Absolute path to the selfie file on local storage (pre-upload).
  final String selfiePath;

  /// The actual moment the check-in/out happened (captured client-side,
  /// not when it eventually syncs).
  final DateTime recordedAt;

  final AttendanceSyncStatus status;

  /// Last error message from a failed sync attempt, if any.
  final String? errorMessage;

  bool get isPending => status == AttendanceSyncStatus.pending;
  bool get isSynced => status == AttendanceSyncStatus.synced;
  bool get isFailed => status == AttendanceSyncStatus.failed;

  PendingAttendanceRecord copyWith({
    int? id,
    String? selfiePath,
    AttendanceSyncStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) => PendingAttendanceRecord(
    id: id ?? this.id,
    type: type,
    latitude: latitude,
    longitude: longitude,
    selfiePath: selfiePath ?? this.selfiePath,
    recordedAt: recordedAt,
    status: status ?? this.status,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
  );

  factory PendingAttendanceRecord.fromMap(Map<String, dynamic> map) =>
      PendingAttendanceRecord(
        id: map['id'] as int?,
        type: AttendanceType.fromString(map['type'] as String?),
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        selfiePath: map['selfie_path'] as String,
        recordedAt: DateTime.parse(map['recorded_at'] as String),
        status: AttendanceSyncStatus.fromString(map['status'] as String?),
        errorMessage: map['error_message'] as String?,
      );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'type': type.apiValue,
    'latitude': latitude,
    'longitude': longitude,
    'selfie_path': selfiePath,
    'recorded_at': recordedAt.toIso8601String(),
    'status': status.name,
    'error_message': errorMessage,
  };
}
