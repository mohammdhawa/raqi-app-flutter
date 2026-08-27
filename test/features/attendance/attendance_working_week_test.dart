import 'package:doc_approval/features/attendance/domain/attendance_window.dart';
import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:flutter_test/flutter_test.dart';

/// The backend's calendar has no weekly day off: `attendance.working_days`
/// lists all seven days, and so does `AttendanceService::DEFAULT_WORKING_DAYS`
/// (the fallback for a missing config). The client mirror must agree — and,
/// where it cannot know, must err towards letting the request through.
///
/// These dates are in August 2026: the 21st and 28th are Fridays, the 22nd
/// and 29th Saturdays — the two days a previous policy treated as a weekend,
/// pinned here precisely because they are the ones most likely to regress.
void main() {
  final friday = DateTime(2026, 8, 21);
  final saturday = DateTime(2026, 8, 22);
  final sunday = DateTime(2026, 8, 23);

  group('isWorkingDay', () {
    test('every day of the week is a working day', () {
      final nonWorking = <DateTime>[
        for (var d = 22; d <= 28; d++)
          if (!isWorkingDay(DateTime(2026, 8, d))) DateTime(2026, 8, d),
      ];

      expect(nonWorking, isEmpty);
    });

    test('Friday and Saturday are working days like any other', () {
      expect(friday.weekday, DateTime.friday);
      expect(saturday.weekday, DateTime.saturday);
      expect(isWorkingDay(friday), isTrue);
      expect(isWorkingDay(saturday), isTrue);
    });
  });

  group('checkInBlockedReason', () {
    // The mirror is deliberately permissive: it must never invent a day off
    // the server does not have, which would block a check-in the backend
    // would accept and leave the employee with no way through.
    test('no day of the week pre-blocks check-in', () {
      for (var d = 22; d <= 28; d++) {
        expect(
          checkInBlockedReason(DateTime(2026, 8, d, 9)),
          isNull,
          reason: '2026-08-$d must not be pre-blocked',
        );
      }
    });

    test('check-in stays open around the clock', () {
      expect(checkInBlockedReason(DateTime(2026, 8, 21, 4)), isNull);
      expect(checkInBlockedReason(DateTime(2026, 8, 21, 23, 30)), isNull);
    });
  });

  group('workingDaysBetween', () {
    test('a span crossing a Friday charges it', () {
      // Sat 22 → Sun 30: 9 calendar days, and all 9 are counted.
      expect(daysBetween(saturday, DateTime(2026, 8, 30)), 9);
      expect(workingDaysBetween(saturday, DateTime(2026, 8, 30)), 9);
    });

    test('Sunday to Saturday costs seven days', () {
      expect(workingDaysBetween(sunday, DateTime(2026, 8, 29)), 7);
    });

    test('a Friday-only period is worth one day, not zero', () {
      expect(workingDaysBetween(friday, friday), 1);
    });

    test('it matches the plain calendar count while no day is skipped', () {
      for (var d = 15; d <= 25; d++) {
        final start = DateTime(2026, 8, 15);
        final end = DateTime(2026, 8, d);
        expect(workingDaysBetween(start, end), daysBetween(start, end));
      }
    });

    test('a reversed span is zero, not negative', () {
      expect(workingDaysBetween(sunday, saturday), 0);
    });
  });
}
