import 'package:doc_approval/features/attendance/domain/attendance_action.dart';
import 'package:doc_approval/features/attendance/domain/attendance_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 18, 9);

  test('no record → check-in allowed', () {
    final a = resolveAttendanceAction(
      status: null,
      onApprovedLeave: false,
      checkoutBlockedReason: null,
      now: now,
    );
    expect(a.nextType, AttendanceType.checkIn);
    expect(a.disabledReason, isNull);
  });

  test('checked out → second check-in blocked with the existing message', () {
    final a = resolveAttendanceAction(
      status: AttendanceType.checkOut,
      onApprovedLeave: false,
      checkoutBlockedReason: null,
      now: now,
    );
    expect(a.nextType, AttendanceType.checkIn);
    expect(
      a.disabledReason,
      'لقد أكملت دوام اليوم — تم تسجيل الحضور والانصراف.',
    );
  });

  test('approved leave blocks check-in', () {
    final a = resolveAttendanceAction(
      status: null,
      onApprovedLeave: true,
      checkoutBlockedReason: null,
      now: now,
    );
    expect(a.disabledReason, 'لديك إجازة معتمدة اليوم — لا حاجة لتسجيل الحضور.');
  });

  test('checked in → checkout carries the gap countdown', () {
    final a = resolveAttendanceAction(
      status: AttendanceType.checkIn,
      onApprovedLeave: false,
      checkoutBlockedReason: 'انتظر',
      now: now,
    );
    expect(a.nextType, AttendanceType.checkOut);
    expect(a.disabledReason, 'انتظر');
  });
}
