import 'attendance_record.dart';
import 'attendance_window.dart';

/// What the employee can do next about attendance, and why not if they can't.
///
/// Shared by the attendance screen and the home hero card so both agree on
/// the next action and on when it is pre-disabled.
class AttendanceAction {
  const AttendanceAction({required this.nextType, this.disabledReason});

  /// The action the primary button performs.
  final AttendanceType nextType;

  /// Arabic reason [nextType] is pre-disabled, or `null` when it is allowed.
  final String? disabledReason;
}

/// Resolves the next check-in/out action from today's [status].
///
/// Pre-disables the action whenever we can already predict the server will
/// reject it — cutting down on failed round-trips. The server still has the
/// final say either way.
AttendanceAction resolveAttendanceAction({
  required AttendanceType? status,
  required bool onApprovedLeave,
  required String? checkoutBlockedReason,
  required DateTime now,
}) {
  final nextType = status?.opposite ?? AttendanceType.checkIn;

  String? disabledReason;
  if (nextType == AttendanceType.checkIn) {
    // Blocked once the day is complete or on approved leave. A checkout for
    // today (missing-checkout records are excluded upstream) means the
    // single daily shift is already done — no second check-in.
    // checkInBlockedReason stays in the chain even though the calendar no
    // longer blocks anything: it is the one hook a future day-off rule
    // would come back through.
    if (status == AttendanceType.checkOut) {
      disabledReason = 'لقد أكملت دوام اليوم — تم تسجيل الحضور والانصراف.';
    } else {
      disabledReason = checkInBlockedReason(now);
      if (disabledReason == null && onApprovedLeave) {
        disabledReason = 'لديك إجازة معتمدة اليوم — لا حاجة لتسجيل الحضور.';
      }
    }
  } else {
    // Checking out: block until the backend's minimum check-in→checkout gap
    // has elapsed, showing a live countdown while it hasn't.
    disabledReason = checkoutBlockedReason;
  }

  return AttendanceAction(nextType: nextType, disabledReason: disabledReason);
}
