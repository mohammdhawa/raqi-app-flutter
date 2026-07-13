import 'package:doc_approval/features/attendance/domain/attendance_record.dart';
import 'package:doc_approval/features/attendance/domain/attendance_window.dart';
import 'package:doc_approval/features/attendance/domain/pending_attendance_record.dart';
import 'package:doc_approval/features/attendance/presentation/providers/attendance_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Backend examples: check-in at 08:00 …
  final checkIn = DateTime(2026, 7, 8, 8);

  group('checkout minimum-gap (ATTENDANCE_MIN_CHECKOUT_GAP=60)', () {
    test('checkout 30 minutes after check-in is blocked', () {
      // 08:00 → 08:30 : rejected by the backend, pre-blocked here too.
      expect(checkOutBlockedReason(checkIn, DateTime(2026, 7, 8, 8, 30)),
          isNotNull);
      expect(
        checkoutGapRemaining(checkIn, DateTime(2026, 7, 8, 8, 30)),
        const Duration(minutes: 30),
      );
    });

    test('checkout exactly 60 minutes after check-in is allowed (boundary)', () {
      // 08:00 → 09:00 : the exact boundary is allowed.
      expect(checkOutBlockedReason(checkIn, DateTime(2026, 7, 8, 9)), isNull);
      expect(checkoutGapRemaining(checkIn, DateTime(2026, 7, 8, 9)), isNull);
    });

    test('checkout 61 minutes after check-in is allowed', () {
      // 08:00 → 09:01 : accepted.
      expect(checkOutBlockedReason(checkIn, DateTime(2026, 7, 8, 9, 1)), isNull);
    });

    test('remaining time is rounded up to whole minutes in the message', () {
      // 08:00 → 08:59:10 : 50 s left → "دقيقة واحدة" (never "0 دقائق").
      final reason =
          checkOutBlockedReason(checkIn, DateTime(2026, 7, 8, 8, 59, 10));
      expect(reason, contains('دقيقة واحدة'));
    });

    test('the final sub-second still reads a full minute, never "0 دقائق"', () {
      // 08:00 → 08:59:59.500 : 500 ms left. inSeconds would truncate to 0 and
      // render "0 دقائق"; rounding from millis keeps it "دقيقة واحدة".
      final reason = checkOutBlockedReason(
        checkIn,
        DateTime(2026, 7, 8, 8, 59, 59, 500),
      );
      expect(reason, contains('دقيقة واحدة'));
      expect(reason, isNot(contains('0 دقائق')));
    });
  });

  group('resolveLatestAttendance exposes the governing record', () {
    AttendanceRecord remote(AttendanceType type, DateTime at) => AttendanceRecord(
          id: 1,
          userId: 1,
          type: type,
          latitude: 0,
          longitude: 0,
          recordedAt: at,
          createdAt: at,
        );

    PendingAttendanceRecord local(AttendanceType type, DateTime at) =>
        PendingAttendanceRecord(
          type: type,
          latitude: 0,
          longitude: 0,
          selfiePath: 'selfie.jpg',
          recordedAt: at,
        );

    test('returns the check-in time while checked in (drives the countdown)',
        () {
      final latest = resolveLatestAttendance(
        remoteRecords: [remote(AttendanceType.checkIn, checkIn)],
        localRecords: const [],
        now: DateTime(2026, 7, 8, 10),
      );
      expect(latest?.type, AttendanceType.checkIn);
      expect(latest?.recordedAt, checkIn);
    });

    test('uses a locally-queued check-in that has not synced yet', () {
      final latest = resolveLatestAttendance(
        remoteRecords: const [],
        localRecords: [local(AttendanceType.checkIn, checkIn)],
        now: DateTime(2026, 7, 8, 10),
      );
      expect(latest?.type, AttendanceType.checkIn);
      expect(latest?.recordedAt, checkIn);
    });

    test('reports checkout (no min-gap block) once the day is closed', () {
      final latest = resolveLatestAttendance(
        remoteRecords: [
          remote(AttendanceType.checkIn, checkIn),
          remote(AttendanceType.checkOut, DateTime(2026, 7, 8, 16)),
        ],
        localRecords: const [],
        now: DateTime(2026, 7, 8, 17),
      );
      expect(latest?.type, AttendanceType.checkOut);
    });
  });
}
