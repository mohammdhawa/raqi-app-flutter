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
    this.isMissingCheckout = false,
    this.isRejected = false,
    this.rejectionMessage,
    this.workHours,
    this.errorMessage,
    this.localId,
  });

  factory TodayAttendanceItem.remote(AttendanceRecord record) =>
      TodayAttendanceItem._(
        type: record.type,
        recordedAt: record.recordedAt,
        status: AttendanceSyncStatus.synced,
        isMissingCheckout: record.isMissingCheckout,
        isRejected: record.isRejected,
        rejectionMessage: record.isRejected
            ? _rejectionMessage(record)
            : null,
        workHours: record.workHours,
      );

  factory TodayAttendanceItem.local(PendingAttendanceRecord record) =>
      TodayAttendanceItem._(
        type: record.type,
        recordedAt: record.recordedAt,
        status: record.status,
        errorMessage: record.errorMessage,
        localId: record.id,
      );

  final AttendanceType type;
  final DateTime recordedAt;

  /// Local sync status (synced / pending / failed) — drives the badge.
  final AttendanceSyncStatus status;

  /// Server-side `missing_checkout` flag on a check-in: the employee never
  /// closed the day, so it must render as incomplete, not a full day.
  final bool isMissingCheckout;

  /// HR refused this record. The row is still listed — the employee was
  /// notified about it and needs to find it — but it must never read as an
  /// attendance record that counts.
  final bool isRejected;

  /// Why it was refused, ready to display. `null` unless [isRejected].
  final String? rejectionMessage;

  /// Worked hours on a checkout row, if the server computed them.
  final double? workHours;

  /// Why this queued record was rejected by the server (business-rule 422),
  /// shown inline on a failed row. `null` unless [status] is `failed`.
  final String? errorMessage;

  /// Local-queue row id — present only for queued (non-remote) entries, so
  /// a rejected one can be dismissed.
  final int? localId;
}

/// The refusal, phrased for the employee — the same sentence the push
/// notification carried, so the row and the notification agree.
String _rejectionMessage(AttendanceRecord record) {
  final what = record.type == AttendanceType.checkOut ? 'انصرافك' : 'حضورك';
  final note = record.rejectionNote == null || record.rejectionNote!.isEmpty
      ? ''
      : ' ملاحظة: ${record.rejectionNote}';

  return 'لم يتم قبول تسجيل $what: ${record.rejectionReasonLabel}.$note';
}
