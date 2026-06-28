/// Client-side mirror of the server's check-in rules — used only to
/// pre-disable the check-in button and explain why, reducing failed
/// attempts. The backend remains the source of truth: it still validates
/// every record and rejects with HTTP 422 + an Arabic `message`.
///
/// Context (single timezone Asia/Damascus, single shift, no overnight):
///   • Working days are Sunday–Thursday; Friday & Saturday are off.
///   • Check-in is allowed only between 06:00 and 17:00.
library;

/// Earliest hour (inclusive) a check-in is accepted.
const int kCheckInStartHour = 6;

/// First hour at which check-in is no longer accepted (i.e. 17:00 onward).
const int kCheckInEndHour = 17;

/// Sun–Thu are working days; Fri & Sat are off.
bool isWorkingDay(DateTime d) =>
    d.weekday != DateTime.friday && d.weekday != DateTime.saturday;

/// Whether [now] falls inside the 06:00–17:00 check-in window.
bool isWithinCheckInWindow(DateTime now) =>
    now.hour >= kCheckInStartHour && now.hour < kCheckInEndHour;

/// Returns an Arabic reason the user can't check in right now, or `null`
/// when check-in is currently allowed. Mirrors the server's day/window
/// rules (leave/duplicate checks stay server-side).
String? checkInBlockedReason(DateTime now) {
  if (!isWorkingDay(now)) {
    return 'لا يمكن تسجيل الحضور في أيام العطلة (الجمعة والسبت).';
  }
  if (!isWithinCheckInWindow(now)) {
    return 'تسجيل الحضور متاح فقط بين الساعة 06:00 و 17:00.';
  }
  return null;
}
