import 'package:doc_approval/features/attendance/domain/attendance_record.dart';
import 'package:doc_approval/features/attendance/domain/pending_attendance_record.dart';
import 'package:doc_approval/features/attendance/presentation/providers/attendance_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 7, 8, 10);
  final yesterday = DateTime(2026, 7, 7, 9);

  AttendanceRecord remote({
    required AttendanceType type,
    required DateTime recordedAt,
    String? status,
  }) {
    return AttendanceRecord(
      id: 1,
      userId: 1,
      type: type,
      latitude: 33.5,
      longitude: 36.3,
      recordedAt: recordedAt,
      createdAt: recordedAt,
      status: status,
    );
  }

  PendingAttendanceRecord local({
    required AttendanceType type,
    required DateTime recordedAt,
    AttendanceSyncStatus status = AttendanceSyncStatus.pending,
  }) {
    return PendingAttendanceRecord(
      type: type,
      latitude: 33.5,
      longitude: 36.3,
      selfiePath: 'selfie.jpg',
      recordedAt: recordedAt,
      status: status,
    );
  }

  test('yesterday check-in does not offer checkout on a new day', () {
    final status = resolveAttendanceStatus(
      remoteRecords: [
        remote(type: AttendanceType.checkIn, recordedAt: yesterday),
      ],
      localRecords: const [],
      now: today,
    );

    expect(status, isNull);
  });

  test('auto-closed missing checkout does not remain active', () {
    final status = resolveAttendanceStatus(
      remoteRecords: [
        remote(
          type: AttendanceType.checkIn,
          recordedAt: today,
          status: 'missing_checkout',
        ),
      ],
      localRecords: const [],
      now: today,
    );

    expect(status, isNull);
  });

  test('rejected checkout does not change today status', () {
    final status = resolveAttendanceStatus(
      remoteRecords: const [],
      localRecords: [
        local(
          type: AttendanceType.checkOut,
          recordedAt: today,
          status: AttendanceSyncStatus.failed,
        ),
      ],
      now: today,
    );

    expect(status, isNull);
  });

  test('synced local check-in defers to a remote missing_checkout twin', () {
    // Backend auto-closed the day; the synced local twin must not keep the
    // user "checked in" and keep offering a checkout the server would reject.
    final checkInTime = DateTime(2026, 7, 8, 9);
    final status = resolveAttendanceStatus(
      remoteRecords: [
        remote(
          type: AttendanceType.checkIn,
          recordedAt: checkInTime,
          status: 'missing_checkout',
        ),
      ],
      localRecords: [
        local(
          type: AttendanceType.checkIn,
          recordedAt: checkInTime,
          status: AttendanceSyncStatus.synced,
        ),
      ],
      now: today,
    );

    expect(status, isNull);
  });

  test('latest valid action from today drives status', () {
    final status = resolveAttendanceStatus(
      remoteRecords: [
        remote(
          type: AttendanceType.checkIn,
          recordedAt: today.subtract(const Duration(hours: 2)),
        ),
      ],
      localRecords: [
        local(
          type: AttendanceType.checkOut,
          recordedAt: today.subtract(const Duration(hours: 1)),
        ),
      ],
      now: today,
    );

    expect(status, AttendanceType.checkOut);
  });
}
