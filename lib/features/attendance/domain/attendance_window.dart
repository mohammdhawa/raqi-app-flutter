/// Client-side mirror of the server's check-in rules — used only to
/// pre-disable the check-in button and explain why, reducing failed
/// attempts. The backend remains the source of truth: it still validates
/// every record and rejects with HTTP 422 + an Arabic `message`.
///
/// Context (single timezone Asia/Damascus, single shift, no overnight):
///   • There is no weekly day off — `working_days` lists all seven days.
///   • Check-in is open 24 hours; there is no time-of-day window.
///
/// These mirror the server config (`working_days = [0,1,2,3,4,5,6]`, empty
/// check-in window). Leave / duplicate / leave-overlap checks stay
/// server-side, so there is no day or time reason to block check-in here.
///
/// The weekly calendar is server configuration and has changed more than
/// once. The mirror below therefore stays deliberately PERMISSIVE: a day off
/// the device does not know about costs a round trip and an Arabic server
/// message, while a day off the device invents blocks a check-in the server
/// would have accepted — and leaves the employee with no way through. Never
/// hardcode a weekend here; if a day-off calendar comes back (a public
/// holiday list is the likely next form), it has to arrive from the API.
library;

/// Whether [d] is a working day. Every day currently is, mirroring the
/// backend's `attendance.working_days` (`[0,1,2,3,4,5,6]`, Sunday=0). Also
/// drives the leave preview's counted days (see [workingDaysBetween] in
/// leave.dart), which the server computes from the same calendar.
bool isWorkingDay(DateTime d) => true;

/// Check-in is open 24 hours; there is no time-of-day restriction.
bool isWithinCheckInWindow(DateTime now) => true;

/// Returns an Arabic reason the user can't check in right now, or `null`
/// when check-in is currently allowed.
///
/// Always `null` today: with every day a working day and check-in open 24/7,
/// nothing about the calendar is predictable enough to pre-block, and the
/// remaining rules (approved leave, duplicate check-in) are enforced
/// server-side — their 422 message is surfaced on the record's own tile.
/// Kept as the single hook the check-in screen calls, so a future
/// client-side pre-check has one home.
String? checkInBlockedReason(DateTime now) => null;

/// Default minimum minutes that must elapse between a check-in and its
/// checkout, mirroring the backend's `attendance.min_checkout_gap_minutes`
/// (env `ATTENDANCE_MIN_CHECKOUT_GAP`, default 60; 0 disables it).
///
/// Used only to pre-disable the checkout button on this device. The backend
/// stays authoritative: it may be configured to a different value and still
/// rejects an early checkout with a 422 business-rule message regardless of
/// what this device predicts.
const int defaultMinCheckoutGapMinutes = 60;

/// Time still to wait before checkout is allowed, given a check-in recorded at
/// [checkInAt], or `null` once at least [defaultMinCheckoutGapMinutes] have
/// elapsed. The boundary itself is allowed (exactly 60 minutes → `null`),
/// matching the backend.
Duration? checkoutGapRemaining(DateTime checkInAt, DateTime now) {
  const gap = Duration(minutes: defaultMinCheckoutGapMinutes);
  final elapsed = now.difference(checkInAt);
  return elapsed >= gap ? null : gap - elapsed;
}

/// Arabic reason the checkout button is pre-disabled because fewer than
/// [defaultMinCheckoutGapMinutes] have passed since [checkInAt] — with the
/// remaining wait counted down — or `null` when checkout is allowed. Mirrors
/// the backend's min-gap rule to cut down on failed attempts; the server still
/// has the final say.
String? checkOutBlockedReason(DateTime checkInAt, DateTime now) {
  final remaining = checkoutGapRemaining(checkInAt, now);
  if (remaining == null) return null;
  // Round the sub-second remainder UP (from millis, not truncated seconds) so
  // the final partial minute still reads "دقيقة واحدة" and never "0 دقائق".
  final minutesLeft =
      (remaining.inMilliseconds / Duration.millisecondsPerMinute).ceil();
  return 'لا يمكن تسجيل الانصراف قبل مرور $defaultMinCheckoutGapMinutes دقيقة '
      'على الحضور. يتبقّى ${_arabicMinutes(minutesLeft)}.';
}

/// Grammatically-agreeing Arabic for a minute count in the 1–60 range this
/// countdown produces (singular / dual / 3–10 plural / 11+ singular-form).
String _arabicMinutes(int n) {
  if (n == 1) return 'دقيقة واحدة';
  if (n == 2) return 'دقيقتان';
  if (n <= 10) return '$n دقائق';
  return '$n دقيقة';
}
