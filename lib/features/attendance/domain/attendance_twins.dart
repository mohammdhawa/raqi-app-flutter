import 'attendance_record.dart';
import 'pending_attendance_record.dart';

/// Whether [local] is the same logical check-in/out as a record the server
/// already returned — matched by type and near-identical time. Used both to
/// let the authoritative remote copy govern status and to avoid showing a
/// duplicate tile in "today's records".
bool hasRemoteTwin(
  PendingAttendanceRecord local,
  Iterable<AttendanceRecord> remoteRecords,
) {
  return remoteRecords.any(
    (rt) =>
        rt.type == local.type &&
        rt.recordedAt.difference(local.recordedAt).abs() <
            const Duration(minutes: 2),
  );
}
