// Reading ids out of the loosely typed maps that reach the app from outside
// it — FCM `data` payloads and the notification list's `data` column.

/// An id from a notification payload, whatever spelling it arrived in.
///
/// The same `leave_request_id` reaches the app as `'42'` through FCM (which
/// stringifies every `data` value), as `42` through `GET /notifications`, and
/// as `42.0` from a console-sent test push. Returns null when the value is
/// absent or is not a number in any of those spellings — callers read that as
/// "this payload does not route anywhere".
///
/// Kept in one place because every deep link depends on it: three byte-identical
/// copies used to sit in the push service, the router and the notification
/// model, so a future tolerance change (rejecting 0, trimming whitespace) would
/// have had to be made three times or the deep links would disagree.
int? payloadId(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString());
}
