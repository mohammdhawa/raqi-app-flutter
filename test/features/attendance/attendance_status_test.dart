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
    bool isRejected = false,
    String? rejectionReason,
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
      isRejected: isRejected,
      rejectionReason: rejectionReason,
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

  // HR refusing a check-in is how they tell the employee to record the day
  // again. The server stops seeing the refused row, so if the app kept treating
  // it as attendance it would offer "check out" and every tap would 422 —
  // leaving the employee with no way to do what they were asked.
  test('an HR-refused check-in leaves the day open to be recorded again', () {
    final status = resolveAttendanceStatus(
      remoteRecords: [
        remote(
          type: AttendanceType.checkIn,
          recordedAt: today,
          isRejected: true,
          rejectionReason: 'location',
        ),
      ],
      localRecords: const [],
      now: today,
    );

    expect(status, isNull);
  });

  // The screen derives its button from resolveLatestAttendance: no valid
  // record means "تسجيل حضور". Asserted at that level too, because it is the
  // employee-visible half of the rule — the notification told them to record
  // the day again, and the button has to let them.
  test('a refused check-in leaves the button on check-in, not check-out', () {
    final latest = resolveLatestAttendance(
      remoteRecords: [
        remote(
          type: AttendanceType.checkIn,
          recordedAt: today,
          isRejected: true,
          rejectionReason: 'location',
        ),
      ],
      localRecords: const [],
      now: today,
    );

    expect(latest, isNull);
    // How attendance_screen.dart computes the action it offers.
    expect(latest?.type.opposite ?? AttendanceType.checkIn,
        AttendanceType.checkIn);
  });

  // Refusal is not stored in `status`, so a row can be both. The refusal is
  // the actionable one — and either flag alone already frees the day.
  test('a record that is both missing_checkout and refused stays excluded',
      () {
    final record = AttendanceRecord.fromJson({
      'id': 1,
      'user_id': 1,
      'type': 'check_in',
      'latitude': '33.5',
      'longitude': '36.3',
      'recorded_at': today.toIso8601String(),
      'created_at': today.toIso8601String(),
      'status': 'missing_checkout',
      'rejected_at': '2026-07-08T12:00:00.000000Z',
      'rejection_reason': 'selfie',
    });

    expect(record.isMissingCheckout, isTrue);
    expect(record.isRejected, isTrue);
    expect(
      resolveAttendanceStatus(
        remoteRecords: [record],
        localRecords: const [],
        now: today,
      ),
      isNull,
    );
  });

  test('a refused check-in is ignored in favour of the accepted retry', () {
    final status = resolveAttendanceStatus(
      remoteRecords: [
        remote(
          type: AttendanceType.checkIn,
          recordedAt: DateTime(2026, 7, 8, 8),
          isRejected: true,
          rejectionReason: 'selfie',
        ),
        remote(type: AttendanceType.checkIn, recordedAt: DateTime(2026, 7, 8, 9)),
      ],
      localRecords: const [],
      now: today,
    );

    expect(status, AttendanceType.checkIn);
  });

  // The local queue keeps synced rows. Once the server refuses the record, the
  // local copy must not resurrect it — _hasRemoteTwin hands authority to the
  // (now excluded) remote one.
  test('a synced local check-in does not survive its remote copy being refused', () {
    final recordedAt = DateTime(2026, 7, 8, 8);

    final status = resolveAttendanceStatus(
      remoteRecords: [
        remote(
          type: AttendanceType.checkIn,
          recordedAt: recordedAt,
          isRejected: true,
          rejectionReason: 'location',
        ),
      ],
      localRecords: [
        local(
          type: AttendanceType.checkIn,
          recordedAt: recordedAt,
          status: AttendanceSyncStatus.synced,
        ),
      ],
      now: today,
    );

    expect(status, isNull);
  });

  test('a record from a backend without refusals still counts', () {
    final record = AttendanceRecord.fromJson({
      'id': 1,
      'user_id': 1,
      'type': 'check_in',
      'latitude': '33.5',
      'longitude': '36.3',
      'recorded_at': today.toIso8601String(),
      'created_at': today.toIso8601String(),
    });

    expect(record.isRejected, isFalse);
    expect(
      resolveAttendanceStatus(
        remoteRecords: [record],
        localRecords: const [],
        now: today,
      ),
      AttendanceType.checkIn,
    );
  });

  test('is_rejected is read from the payload', () {
    final record = AttendanceRecord.fromJson({
      'id': 1,
      'user_id': 1,
      'type': 'check_in',
      'latitude': '33.5',
      'longitude': '36.3',
      'recorded_at': today.toIso8601String(),
      'created_at': today.toIso8601String(),
      'is_rejected': true,
      'rejection_reason': 'location',
      'rejection_note': 'خارج نطاق الموقع',
    });

    expect(record.isRejected, isTrue);
    expect(record.rejectionReasonLabel, 'الموقع المسجَّل لا يطابق موقع العمل');
    expect(record.rejectionNote, 'خارج نطاق الموقع');
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
