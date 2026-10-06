import 'package:doc_approval/features/attendance/domain/attendance_capture_draft.dart';
import 'package:doc_approval/features/attendance/domain/attendance_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final openedAt = DateTime(2026, 9, 30, 16, 0);

  AttendanceCaptureDraft draft({int userId = 7, DateTime? at}) =>
      AttendanceCaptureDraft(
        operationId: 'op-1',
        userId: userId,
        type: AttendanceType.checkOut,
        latitude: 33.5,
        longitude: 36.3,
        cameraOpenedAt: at ?? openedAt,
      );

  /// [photoAge] is how long before "now" the photo was taken; by default it
  /// came back just before the cold start.
  CaptureRecoveryDecision decide({
    AttendanceCaptureDraft? draft,
    int currentUserId = 7,
    Duration elapsed = const Duration(minutes: 1),
    String? image,
    Duration photoAge = const Duration(seconds: 5),
    bool alreadyQueued = false,
  }) {
    final now = openedAt.add(elapsed);
    return decideCaptureRecovery(
      draft: draft,
      currentUserId: currentUserId,
      now: now,
      recoveredPhoto:
          image == null ? null : (path: image, takenAt: now.subtract(photoAge)),
      alreadyQueued: alreadyQueued,
    );
  }

  group('decideCaptureRecovery', () {
    test('no draft and no image: nothing to do', () {
      expect(decide(), isA<CaptureRecoveryNothing>());
    });

    test('recovered image with no draft is discarded, never queued', () {
      expect(decide(image: '/cache/a.jpg'), isA<CaptureRecoveryNothing>());
    });

    test('fresh draft for the same user plus an image is queued', () {
      final d = draft();
      final decision = decide(draft: d, image: '/cache/a.jpg');

      expect(decision, isA<CaptureRecoveryQueue>());
      decision as CaptureRecoveryQueue;
      expect(decision.draft, same(d));
      expect(decision.imagePath, '/cache/a.jpg');
    });

    test(
        'a queued photo is recorded at the time it came back, not when the '
        'camera opened', () {
      final decision = decide(
        draft: draft(),
        elapsed: const Duration(minutes: 3),
        image: '/cache/a.jpg',
        photoAge: const Duration(seconds: 20),
      ) as CaptureRecoveryQueue;

      expect(
        decision.recordedAt,
        openedAt.add(const Duration(minutes: 3) - const Duration(seconds: 20)),
      );
    });

    test('a photo time outside [camera opened, now] is clamped into it', () {
      final early = decide(
        draft: draft(),
        elapsed: const Duration(minutes: 2),
        image: '/cache/a.jpg',
        photoAge: const Duration(minutes: 10),
      ) as CaptureRecoveryQueue;
      expect(early.recordedAt, openedAt);

      final late = decide(
        draft: draft(),
        elapsed: const Duration(minutes: 2),
        image: '/cache/a.jpg',
        photoAge: const Duration(minutes: -1),
      ) as CaptureRecoveryQueue;
      expect(late.recordedAt, openedAt.add(const Duration(minutes: 2)));
    });

    test("another user's draft is discarded silently, image or not", () {
      expect(
        decide(draft: draft(userId: 99), image: '/cache/a.jpg'),
        isA<CaptureRecoveryDiscard>(),
      );
      expect(decide(draft: draft(userId: 99)), isA<CaptureRecoveryDiscard>());
    });

    test(
        'a draft from an hour ago is expired: a just-taken image is not '
        'submitted, and the employee is told to retry', () {
      expect(
        decide(
          draft: draft(),
          elapsed: const Duration(hours: 1),
          image: '/cache/a.jpg',
        ),
        isA<CaptureRecoveryIncomplete>(),
      );
    });

    test('an expired draft with no image was abandoned: cleared silently', () {
      expect(
        decide(draft: draft(), elapsed: const Duration(days: 2)),
        isA<CaptureRecoveryStale>(),
      );
    });

    test('an expired draft whose image is old too is cleared silently', () {
      expect(
        decide(
          draft: draft(),
          elapsed: const Duration(days: 2),
          image: '/cache/a.jpg',
          photoAge: const Duration(days: 1),
        ),
        isA<CaptureRecoveryStale>(),
      );
    });

    test('expiry follows the named TTL at its boundary', () {
      expect(
        decide(
          draft: draft(),
          elapsed: attendanceCaptureDraftTtl - const Duration(seconds: 1),
          image: '/cache/a.jpg',
        ),
        isA<CaptureRecoveryQueue>(),
      );
      expect(
        decide(
          draft: draft(),
          elapsed: attendanceCaptureDraftTtl + const Duration(seconds: 1),
          image: '/cache/a.jpg',
        ),
        isA<CaptureRecoveryIncomplete>(),
      );
    });

    test('a draft stamped in the future (clock moved back) is not trusted', () {
      expect(
        decide(
          draft: draft(),
          elapsed: const Duration(minutes: -3),
          image: '/cache/a.jpg',
        ),
        isA<CaptureRecoveryIncomplete>(),
      );
    });

    test('an operation already in the queue is never queued twice', () {
      expect(
        decide(draft: draft(), image: '/cache/a.jpg', alreadyQueued: true),
        isA<CaptureRecoveryAlreadyQueued>(),
      );
    });

    test('an already-queued operation stays silent even without an image', () {
      // The normal path queued it, then the process died before the draft
      // was cleared — that capture completed; no "retry" message.
      expect(
        decide(draft: draft(), alreadyQueued: true),
        isA<CaptureRecoveryAlreadyQueued>(),
      );
    });

    test('fresh draft with no recovered image reports an incomplete capture',
        () {
      final d = draft();
      final decision = decide(draft: d);

      expect(decision, isA<CaptureRecoveryIncomplete>());
      expect((decision as CaptureRecoveryIncomplete).draft, same(d));
    });
  });

  group('AttendanceCaptureDraft', () {
    test('round-trips through its storage map', () {
      final restored = AttendanceCaptureDraft.fromMap(draft().toMap());

      expect(restored.operationId, 'op-1');
      expect(restored.userId, 7);
      expect(restored.type, AttendanceType.checkOut);
      expect(restored.latitude, 33.5);
      expect(restored.longitude, 36.3);
      expect(restored.cameraOpenedAt, openedAt);
    });

    test('operation ids do not repeat across captures', () {
      final ids = {for (var i = 0; i < 1000; i++) newAttendanceOperationId()};
      expect(ids, hasLength(1000));
    });
  });
}
