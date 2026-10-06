import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:flutter_test/flutter_test.dart';

/// HR cut an approved leave short because the employee came back to work.
///
/// The app is the employee's side of that, and it needs no new action — the
/// action is HR's, and the endpoint answers 403 to the employee. What the app
/// has to get right is what it does with the row afterwards, because that row
/// is what decides whether the check-in button is enabled:
/// `approvedLeaveTodayProvider` blocks the button while some approved request
/// covers today.
///
/// Both endings are read purely off the fields the server already sends, so
/// these pin the parsing rather than a widget.
void main() {
  LeaveRequest parse(Map<String, dynamic> json) => LeaveRequest.fromJson({
        'id': 1,
        'leave_type': 'annual',
        'deducts_balance': true,
        ...json,
      });

  /// The provider's own test: approved AND covering the day.
  bool blocksCheckInOn(LeaveRequest r, DateTime day) =>
      r.isApproved && r.coversDate(day);

  group('a leave shortened because the employee came back', () {
    test('stops covering the day they returned, which frees the check-in', () {
      // Granted 20th–25th, ended on the 22nd when the employee turned up.
      final leave = parse({
        'status': 'approved',
        'start_date': '2026-06-20',
        'end_date': '2026-06-21',
      });

      expect(blocksCheckInOn(leave, DateTime(2026, 6, 22)), isFalse);
      // …and every later day it used to cover.
      expect(blocksCheckInOn(leave, DateTime(2026, 6, 25)), isFalse);
    });

    test('still covers the days actually taken', () {
      final leave = parse({
        'status': 'approved',
        'start_date': '2026-06-20',
        'end_date': '2026-06-21',
      });

      // The approval was not undone, so these days are still leave and the
      // employee is still not expected to check in on them.
      expect(blocksCheckInOn(leave, DateTime(2026, 6, 20)), isTrue);
      expect(blocksCheckInOn(leave, DateTime(2026, 6, 21)), isTrue);
      expect(leave.status, LeaveStatus.approved);
    });
  });

  group('a leave cancelled because they returned on its first day', () {
    test('is not read as pending', () {
      final leave = parse({
        'status': 'cancelled',
        'start_date': '2026-06-20',
        'end_date': '2026-06-25',
      });

      // The bug this guards: an unmapped status fell through to `pending`, so a
      // row the server is done with was shown to the employee as still waiting
      // on a decision that is never coming.
      expect(leave.status, LeaveStatus.cancelled);
      expect(leave.isPending, isFalse);
      expect(leave.status.arabicLabel, 'ملغاة');
    });

    test('never blocks the check-in, on any day it used to cover', () {
      final leave = parse({
        'status': 'cancelled',
        'start_date': '2026-06-20',
        'end_date': '2026-06-25',
      });

      expect(leave.isApproved, isFalse);
      for (var day = 20; day <= 25; day++) {
        expect(
          blocksCheckInOn(leave, DateTime(2026, 6, day)),
          isFalse,
          reason: 'June $day should be free once the leave is cancelled',
        );
      }
    });

    test('round-trips through apiValue', () {
      expect(LeaveStatus.cancelled.apiValue, 'cancelled');
      expect(
        LeaveStatus.fromString(LeaveStatus.cancelled.apiValue),
        LeaveStatus.cancelled,
      );
    });
  });

  test('an unknown status still falls back to pending', () {
    // The fallback is deliberate and stays: a value this build has never heard
    // of is safer shown as undecided than as approved, which would wrongly
    // block the check-in.
    expect(LeaveStatus.fromString('something_new'), LeaveStatus.pending);
    expect(LeaveStatus.fromString(null), LeaveStatus.pending);
  });
}
