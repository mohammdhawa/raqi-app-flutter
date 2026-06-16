import 'attendance_record.dart';
import 'pending_attendance_record.dart';

/// A single row in "Today's records" (سجلات اليوم) on the attendance home
/// screen — either a record the server has already confirmed (captured on
/// this device or another one), or one still sitting in this device's
/// local queue, not yet confirmed synced.
class TodayAttendanceItem {
  const TodayAttendanceItem._({
    required this.type,
    required this.recordedAt,
    required this.status,
  });

  factory TodayAttendanceItem.remote(AttendanceRecord record) =>
      TodayAttendanceItem._(
        type: record.type,
        recordedAt: record.recordedAt,
        status: AttendanceSyncStatus.synced,
      );

  factory TodayAttendanceItem.local(PendingAttendanceRecord record) =>
      TodayAttendanceItem._(
        type: record.type,
        recordedAt: record.recordedAt,
        status: record.status,
      );

  final AttendanceType type;
  final DateTime recordedAt;
  final AttendanceSyncStatus status;
}
