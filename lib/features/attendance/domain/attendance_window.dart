/// Client-side mirror of the server's check-in rules — used only to
/// pre-disable the check-in button and explain why, reducing failed
/// attempts. The backend remains the source of truth: it still validates
/// every record and rejects with HTTP 422 + an Arabic `message`.
///
/// Context (single timezone Asia/Damascus, single shift, no overnight):
///   • Every day is a working day — Friday & Saturday included.
///   • Check-in is open 24 hours; there is no time-of-day window.
///
/// These mirror the server config (`working_days` = all 7 days, empty
/// check-in window). Leave / duplicate / leave-overlap checks stay
/// server-side, so there is no day/time reason to block check-in here.
library;

/// Every day is a working day (weekends included). Also drives the leave
/// preview's chargeable-day count (see [workingDaysBetween] in leave.dart),
/// so weekends now count toward leave balance too.
bool isWorkingDay(DateTime d) => true;

/// Check-in is open 24 hours; there is no time-of-day restriction.
bool isWithinCheckInWindow(DateTime now) => true;

/// Returns an Arabic reason the user can't check in right now, or `null`
/// when check-in is currently allowed. Day and time no longer block
/// check-in (open 24/7); the remaining rules (leave, duplicate) are enforced
/// server-side, so this is always `null` today. Kept as the single hook the
/// check-in screen calls, so a future client-side pre-check has one home.
String? checkInBlockedReason(DateTime now) => null;
