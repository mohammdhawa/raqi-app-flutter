import 'dart:math';

import 'attendance_record.dart';

/// How long after the camera opened a capture draft may still be completed
/// from a recovered photo.
///
/// Long enough to cover a slow camera session plus the cold start that
/// follows a kill (splash, session restore); short enough that a photo
/// surfacing much later is never filed against a tap the employee has since
/// forgotten or already redone.
const attendanceCaptureDraftTtl = Duration(minutes: 5);

/// What the device knew at the moment an employee committed to a check-in/out,
/// written to SQLite BEFORE the external camera opens.
///
/// Some OEM builds (MIUI/HyperOS's camera "boost" killer on Redmi devices)
/// SIGKILL the app while the system camera is in front. The photo still comes
/// back — Android cold-starts a new process to deliver it — but every
/// in-memory value from the tap is gone. This draft is how the new process
/// learns what the photo was for. See `AttendanceCaptureRecovery`.
class AttendanceCaptureDraft {
  const AttendanceCaptureDraft({
    required this.operationId,
    required this.userId,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.cameraOpenedAt,
  });

  /// Unique per capture; also stamped on the queue row it produces, which is
  /// what makes recovery exactly-once. The backend has no idempotency key, so
  /// this never leaves the device.
  final String operationId;

  final int userId;
  final AttendanceType type;
  final double latitude;
  final double longitude;

  /// When the camera was about to open — after the GPS fix, so a slow fix
  /// doesn't use up [attendanceCaptureDraftTtl] before the photo is taken.
  final DateTime cameraOpenedAt;

  factory AttendanceCaptureDraft.fromMap(Map<String, dynamic> map) =>
      AttendanceCaptureDraft(
        operationId: map['operation_id'] as String,
        userId: map['user_id'] as int,
        type: AttendanceType.fromString(map['type'] as String?),
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        cameraOpenedAt: DateTime.parse(map['camera_opened_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'operation_id': operationId,
        'user_id': userId,
        'type': type.apiValue,
        'latitude': latitude,
        'longitude': longitude,
        'camera_opened_at': cameraOpenedAt.toIso8601String(),
      };
}

/// A random 128-bit hex id for one capture. No uuid package in the project,
/// and nothing here needs more than uniqueness.
String newAttendanceOperationId() {
  final random = Random.secure();
  return [
    for (var i = 0; i < 16; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// What startup recovery should do with a leftover draft and whatever photo
/// the image picker handed back from a killed process.
sealed class CaptureRecoveryDecision {
  const CaptureRecoveryDecision();
}

/// No draft: nothing was in flight. A recovered photo, if any, is dropped —
/// with no draft there is no type, place or time to file it under.
class CaptureRecoveryNothing extends CaptureRecoveryDecision {
  const CaptureRecoveryNothing();
}

/// Queue the recovered photo using the draft's values, not today's.
class CaptureRecoveryQueue extends CaptureRecoveryDecision {
  const CaptureRecoveryQueue(this.draft, this.imagePath, this.recordedAt);
  final AttendanceCaptureDraft draft;
  final String imagePath;

  /// When the photo came back — the same moment the same-process path
  /// records, so a kill never changes what time the server sees.
  final DateTime recordedAt;
}

/// The draft's operation is already in the queue — the capture completed and
/// only the draft's cleanup was lost. Clear it, say nothing.
class CaptureRecoveryAlreadyQueued extends CaptureRecoveryDecision {
  const CaptureRecoveryAlreadyQueued(this.draft);
  final AttendanceCaptureDraft draft;
}

/// Someone else's draft (shared device). Clear it silently; never submit.
class CaptureRecoveryDiscard extends CaptureRecoveryDecision {
  const CaptureRecoveryDiscard(this.draft);
  final AttendanceCaptureDraft draft;
}

/// The employee's capture did not complete — no photo came back, or it came
/// back too late to trust. Clear the draft and tell them to retry.
class CaptureRecoveryIncomplete extends CaptureRecoveryDecision {
  const CaptureRecoveryIncomplete(this.draft);
  final AttendanceCaptureDraft draft;
}

/// An expired draft with nothing just returned from the camera — a capture
/// abandoned long ago (e.g. swiped away from recents) and most likely redone
/// since. Clear it silently: a "retry" message now would invite a duplicate.
class CaptureRecoveryStale extends CaptureRecoveryDecision {
  const CaptureRecoveryStale(this.draft);
  final AttendanceCaptureDraft draft;
}

/// A photo the image picker handed back from a killed process, and when it
/// was taken (best estimate: its file's modification time).
typedef RecoveredPhoto = ({String path, DateTime takenAt});

/// Pure decision behind startup recovery, kept free of Android, the camera
/// and storage so every branch is unit-testable.
CaptureRecoveryDecision decideCaptureRecovery({
  required AttendanceCaptureDraft? draft,
  required int currentUserId,
  required DateTime now,
  required RecoveredPhoto? recoveredPhoto,
  required bool alreadyQueued,
}) {
  if (draft == null) return const CaptureRecoveryNothing();
  if (draft.userId != currentUserId) return CaptureRecoveryDiscard(draft);
  if (alreadyQueued) return CaptureRecoveryAlreadyQueued(draft);

  if (_isExpired(draft.cameraOpenedAt, now)) {
    // A photo taken moments ago means the employee just finished the camera
    // and is waiting on the result, so it is worth telling them to retry.
    // Without one, the capture was abandoned long ago.
    final photoIsFresh =
        recoveredPhoto != null && !_isExpired(recoveredPhoto.takenAt, now);
    return photoIsFresh
        ? CaptureRecoveryIncomplete(draft)
        : CaptureRecoveryStale(draft);
  }
  if (recoveredPhoto == null) return CaptureRecoveryIncomplete(draft);

  // The file time is only an estimate, so it is clamped to what is known for
  // certain: the photo came back after the camera opened and before now.
  final takenAt = recoveredPhoto.takenAt;
  final recordedAt = takenAt.isBefore(draft.cameraOpenedAt)
      ? draft.cameraOpenedAt
      : (takenAt.isAfter(now) ? now : takenAt);
  return CaptureRecoveryQueue(draft, recoveredPhoto.path, recordedAt);
}

/// Negative age means the clock moved back since [since]: the age is
/// unknowable, so it is treated like an expired one.
bool _isExpired(DateTime since, DateTime now) {
  final age = now.difference(since);
  return age.isNegative || age > attendanceCaptureDraftTtl;
}
