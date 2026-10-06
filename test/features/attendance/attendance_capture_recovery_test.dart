import 'dart:async';
import 'dart:io';

import 'package:doc_approval/features/attendance/data/attendance_local_db.dart';
import 'package:doc_approval/features/attendance/data/selfie_storage.dart';
import 'package:doc_approval/features/attendance/domain/attendance_capture_draft.dart';
import 'package:doc_approval/features/attendance/domain/attendance_record.dart';
import 'package:doc_approval/features/attendance/domain/pending_attendance_record.dart';
import 'package:doc_approval/features/attendance/presentation/providers/attendance_capture_recovery.dart';
import 'package:doc_approval/features/attendance/presentation/providers/attendance_queue_controller.dart';
import 'package:doc_approval/features/attendance/presentation/providers/attendance_sync_service.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

/// In-memory stand-in for the SQLite queue + draft tables. Mirrors the two
/// constraints the real schema enforces: one draft at a time, and a UNIQUE
/// operation_id on queue rows.
class _FakeLocalDb extends Fake implements AttendanceLocalDb {
  final rows = <PendingAttendanceRecord>[];
  final insertedForUserIds = <int>[];
  AttendanceCaptureDraft? draft;
  final clearedOperationIds = <String>[];
  Object? throwOnSaveDraft;
  var _nextId = 1;

  @override
  Future<PendingAttendanceRecord> insert(
    int userId,
    PendingAttendanceRecord record,
  ) async {
    final opId = record.operationId;
    if (opId != null && rows.any((r) => r.operationId == opId)) {
      throw StateError('UNIQUE constraint failed: operation_id');
    }
    final saved = record.copyWith(id: _nextId++);
    rows.add(saved);
    insertedForUserIds.add(userId);
    return saved;
  }

  @override
  Future<List<PendingAttendanceRecord>> getAll(int userId) async =>
      List.of(rows);

  @override
  Future<void> saveCaptureDraft(AttendanceCaptureDraft draft) async {
    final err = throwOnSaveDraft;
    if (err != null) throw err;
    this.draft = draft;
  }

  @override
  Future<AttendanceCaptureDraft?> readCaptureDraft(int claimUserId) async =>
      draft;

  @override
  Future<void> clearCaptureDraft(String operationId, int claimUserId) async {
    clearedOperationIds.add(operationId);
    if (draft?.operationId == operationId) draft = null;
  }

  @override
  Future<bool> hasOperation(String operationId, int userId) async =>
      rows.any((r) => r.operationId == operationId);
}

/// Who is signed in, switchable mid-test (null = signed out).
final _signedInUserId = StateProvider<int?>((ref) => null);

class _FakeSyncService extends Fake implements AttendanceSyncService {
  var syncCalls = 0;

  @override
  Future<void> syncPending() async => syncCalls++;
}

void main() {
  const userId = 7;
  final openedAt = DateTime(2026, 9, 30, 16, 0);

  AttendanceCaptureDraft draftFor({
    String operationId = 'op-1',
    int user = userId,
    AttendanceType type = AttendanceType.checkOut,
  }) =>
      AttendanceCaptureDraft(
        operationId: operationId,
        userId: user,
        type: type,
        latitude: 33.51,
        longitude: 36.29,
        cameraOpenedAt: openedAt,
      );

  Directory tempDir(String prefix) {
    final dir = Directory.systemTemp.createTempSync(prefix);
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return dir;
  }

  /// A photo as the picker leaves it in its cache after a cold start.
  String cachedPhoto() {
    final file = File(
      '${tempDir('picker_cache').path}${Platform.pathSeparator}shot.jpg',
    )..writeAsBytesSync(const [0xFF, 0xD8, 0xFF]);
    return file.path;
  }

  LostDataResponse lostPhoto(String path) => LostDataResponse(
        file: XFile(path),
        files: [XFile(path)],
        type: RetrieveType.image,
      );

  group('captureWithDraft (normal, same-process path)', () {
    test('the draft is on disk before the camera opens', () async {
      final db = _FakeLocalDb();
      final draft = draftFor();
      AttendanceCaptureDraft? draftWhenCameraOpened;

      await captureWithDraft(
        db: db,
        draft: draft,
        captureSelfie: () async {
          draftWhenCameraOpened = db.draft;
          return null;
        },
        enqueue: (r) async => r,
      );

      expect(draftWhenCameraOpened, same(draft));
    });

    test('the camera never opens when the draft cannot be saved', () async {
      final db = _FakeLocalDb()..throwOnSaveDraft = Exception('disk full');
      var cameraOpened = false;

      await expectLater(
        captureWithDraft(
          db: db,
          draft: draftFor(),
          captureSelfie: () async {
            cameraOpened = true;
            return 'attendance_selfies/x.jpg';
          },
          enqueue: (r) async => r,
        ),
        throwsException,
      );
      expect(cameraOpened, isFalse);
    });

    test(
        'a returned photo is queued once under the draft operation and the '
        'draft is cleared', () async {
      final db = _FakeLocalDb();
      final queued = <PendingAttendanceRecord>[];
      final recordedAt = DateTime(2026, 9, 30, 16, 1);
      AttendanceCaptureDraft? draftWhileQueueing;

      final result = await captureWithDraft(
        db: db,
        draft: draftFor(operationId: 'op-normal'),
        captureSelfie: () async => 'attendance_selfies/x.jpg',
        enqueue: (r) async {
          // Still on disk until the row is committed: a kill here must leave
          // startup something to reconcile against.
          draftWhileQueueing = db.draft;
          queued.add(r);
          return r;
        },
        now: () => recordedAt,
      );

      expect(draftWhileQueueing?.operationId, 'op-normal');

      expect(result, isNotNull);
      expect(queued, hasLength(1));
      expect(queued.single.operationId, 'op-normal');
      expect(queued.single.type, AttendanceType.checkOut);
      expect(queued.single.latitude, 33.51);
      expect(queued.single.longitude, 36.29);
      expect(queued.single.selfiePath, 'attendance_selfies/x.jpg');
      expect(queued.single.recordedAt, recordedAt);
      expect(db.draft, isNull);
      expect(db.clearedOperationIds, ['op-normal']);
    });

    test('cancelling the camera leaves no draft and queues nothing', () async {
      final db = _FakeLocalDb();
      var enqueued = false;

      final result = await captureWithDraft(
        db: db,
        draft: draftFor(),
        captureSelfie: () async => null,
        enqueue: (r) async {
          enqueued = true;
          return r;
        },
      );

      expect(result, isNull);
      expect(enqueued, isFalse);
      expect(db.draft, isNull);
    });

    test('a camera error still clears the draft', () async {
      final db = _FakeLocalDb();

      await expectLater(
        captureWithDraft(
          db: db,
          draft: draftFor(),
          captureSelfie: () async => throw PlatformException(code: 'no_cam'),
          enqueue: (r) async => r,
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(db.draft, isNull);
    });
  });

  group('AttendanceCaptureRecovery (startup, after a kill)', () {
    ({
      ProviderContainer container,
      _FakeLocalDb db,
      _FakeSyncService sync,
      Directory support,
      List<String> retrieveCalls,
    }) harness({
      LostDataResponse? lost,
      Object? retrieveThrows,
      Future<void>? retrieveGate,
      bool isAndroid = true,
      Duration sinceOpened = const Duration(minutes: 1),
      Duration photoAge = const Duration(seconds: 5),
      void Function(ProviderContainer)? onPersist,
      int? signedInUser = userId,
    }) {
      final db = _FakeLocalDb();
      final sync = _FakeSyncService();
      final support = tempDir('app_support');
      final retrieveCalls = <String>[];
      final now = openedAt.add(sinceOpened);
      late final ProviderContainer container;
      container = ProviderContainer(overrides: [
        attendanceLocalDbProvider.overrideWithValue(db),
        attendanceSyncServiceProvider.overrideWithValue(sync),
        _signedInUserId.overrideWith((ref) => signedInUser),
        currentUserProvider.overrideWith((ref) {
          final id = ref.watch(_signedInUserId);
          return id == null ? null : User(id: id, name: 'موظف');
        }),
        attendanceCaptureRecoveryProvider.overrideWith(
          (ref) => AttendanceCaptureRecovery(
            ref,
            isAndroid: isAndroid,
            retrieveLostData: () async {
              retrieveCalls.add('call');
              await retrieveGate;
              final err = retrieveThrows;
              if (err != null) throw err;
              return lost ?? LostDataResponse.empty();
            },
            persistSelfie: (f) async {
              final stored = await persistSelfieForUpload(f, baseDir: support);
              onPersist?.call(container);
              return stored;
            },
            photoTakenAt: (_) async => now.subtract(photoAge),
            now: () => now,
          ),
        ),
      ]);
      addTearDown(container.dispose);
      return (
        container: container,
        db: db,
        sync: sync,
        support: support,
        retrieveCalls: retrieveCalls,
      );
    }

    Future<void> recover(ProviderContainer c) =>
        c.read(attendanceCaptureRecoveryProvider).recoverOnce();

    AttendanceCaptureNotice? notice(ProviderContainer c) =>
        c.read(attendanceCaptureNoticeProvider);

    test(
        'matching draft + recovered photo queues exactly one record with the '
        "draft's values", () async {
      final photo = cachedPhoto();
      final h = harness(
        lost: lostPhoto(photo),
        sinceOpened: const Duration(minutes: 2),
        photoAge: const Duration(seconds: 30),
      );
      h.db.draft = draftFor(operationId: 'op-killed');

      await recover(h.container);

      expect(h.db.rows, hasLength(1));
      final row = h.db.rows.single;
      expect(row.operationId, 'op-killed');
      expect(row.type, AttendanceType.checkOut);
      expect(row.latitude, 33.51);
      expect(row.longitude, 36.29);
      // When the photo came back — what the same-process path would record —
      // not when the camera opened.
      expect(row.recordedAt, openedAt.add(const Duration(seconds: 90)));
      expect(row.isPending, isTrue);
      // The photo was moved out of the picker cache into durable storage.
      final stored = File(
        '${h.support.path}${Platform.pathSeparator}${row.selfiePath}',
      );
      expect(stored.existsSync(), isTrue);
      expect(File(photo).existsSync(), isFalse);
      expect(h.db.draft, isNull);
      expect(h.sync.syncCalls, 1);
      expect(notice(h.container)?.outcome, AttendanceCaptureOutcome.recovered);
      expect(notice(h.container)?.type, AttendanceType.checkOut);
      // It lands in the live queue the attendance screen watches.
      expect(
        h.container.read(attendanceQueueProvider).map((r) => r.operationId),
        contains('op-killed'),
      );
    });

    test(
        'retrieveLostData runs once per app start, even if recovery is '
        'triggered again (re-login)', () async {
      final h = harness(lost: lostPhoto(cachedPhoto()));
      h.db.draft = draftFor();

      await recover(h.container);
      h.db.draft = draftFor(operationId: 'op-later');
      await recover(h.container);

      expect(h.retrieveCalls, hasLength(1));
      expect(h.db.rows, hasLength(1));
    });

    test(
        'a second call while recovery is still running waits for it to '
        'finish', () async {
      final gate = Completer<void>();
      final h = harness(
        lost: lostPhoto(cachedPhoto()),
        retrieveGate: gate.future,
      );
      h.db.draft = draftFor();

      final first = recover(h.container);
      var secondDone = false;
      final second = recover(h.container).then((_) => secondDone = true);
      await pumpEventQueue();

      // Returning here would let main.dart's sweep run before the recovered
      // selfie's row exists.
      expect(secondDone, isFalse);

      gate.complete();
      await Future.wait([first, second]);
      expect(h.db.rows, hasLength(1));
      expect(h.retrieveCalls, hasLength(1));
    });

    test(
        "another user's draft: nothing queued, draft cleared, no message, "
        'their photo deleted', () async {
      final photo = cachedPhoto();
      final h = harness(lost: lostPhoto(photo));
      h.db.draft = draftFor(user: 99);

      await recover(h.container);

      expect(h.db.rows, isEmpty);
      expect(h.db.draft, isNull);
      expect(notice(h.container), isNull);
      expect(h.sync.syncCalls, 0);
      expect(File(photo).existsSync(), isFalse);
    });

    test(
        'expired draft with a just-taken photo: not submitted, draft '
        'cleared, retry message', () async {
      final h = harness(
        lost: lostPhoto(cachedPhoto()),
        sinceOpened: const Duration(hours: 2),
      );
      h.db.draft = draftFor();

      await recover(h.container);

      expect(h.db.rows, isEmpty);
      expect(h.db.draft, isNull);
      expect(notice(h.container)?.outcome, AttendanceCaptureOutcome.incomplete);
    });

    test('a draft abandoned long ago with no photo is cleared silently',
        () async {
      final h = harness(sinceOpened: const Duration(days: 2));
      h.db.draft = draftFor();

      await recover(h.container);

      expect(h.db.rows, isEmpty);
      expect(h.db.draft, isNull);
      expect(notice(h.container), isNull);
    });

    test('recovered photo with no draft is discarded and deleted', () async {
      final photo = cachedPhoto();
      final h = harness(lost: lostPhoto(photo));

      await recover(h.container);

      expect(h.db.rows, isEmpty);
      expect(notice(h.container), isNull);
      expect(File(photo).existsSync(), isFalse);
    });

    test('a notice is cleared when the signed-in user changes', () async {
      final h = harness(lost: lostPhoto(cachedPhoto()));
      h.db.draft = draftFor();
      await recover(h.container);
      expect(notice(h.container), isNotNull);

      h.container.read(_signedInUserId.notifier).state = null;
      h.container.read(_signedInUserId.notifier).state = 99;

      expect(notice(h.container), isNull);
    });

    test(
        "a user switch mid-recovery: the capture stays in its owner's queue "
        'and the new user sees no notice', () async {
      final h = harness(
        lost: lostPhoto(cachedPhoto()),
        onPersist: (c) => c.read(_signedInUserId.notifier).state = 99,
      );
      h.db.draft = draftFor();

      await recover(h.container);

      expect(h.db.rows, hasLength(1));
      expect(h.db.insertedForUserIds, [userId]);
      expect(h.db.draft, isNull);
      expect(notice(h.container), isNull);
      // syncPending() would sync the NEW signed-in user's queue, not the
      // original owner's — must not fire for an account that isn't signed
      // in anymore.
      expect(h.sync.syncCalls, 0);
    });

    test('duplicate recovery: an operation already queued is not queued again',
        () async {
      final h = harness(lost: lostPhoto(cachedPhoto()));
      h.db.rows.add(
        PendingAttendanceRecord(
          id: 1,
          type: AttendanceType.checkOut,
          latitude: 33.51,
          longitude: 36.29,
          selfiePath: 'attendance_selfies/first.jpg',
          recordedAt: openedAt,
          operationId: 'op-1',
        ),
      );
      h.db.draft = draftFor(operationId: 'op-1');

      await recover(h.container);

      expect(h.db.rows, hasLength(1));
      expect(h.db.draft, isNull);
      expect(notice(h.container), isNull);
    });

    test(
        'draft with no recovered photo: nothing queued, draft cleared, '
        'retry message naming the action', () async {
      final h = harness();
      h.db.draft = draftFor(type: AttendanceType.checkIn);

      await recover(h.container);

      expect(h.db.rows, isEmpty);
      expect(h.db.draft, isNull);
      expect(notice(h.container)?.outcome, AttendanceCaptureOutcome.incomplete);
      expect(notice(h.container)?.type, AttendanceType.checkIn);
    });

    test('a picker error in the lost-data result counts as no photo', () async {
      final h = harness(
        lost: LostDataResponse(
          exception: PlatformException(code: 'camera_access_denied'),
          type: RetrieveType.image,
        ),
      );
      h.db.draft = draftFor();

      await recover(h.container);

      expect(h.db.rows, isEmpty);
      expect(notice(h.container)?.outcome, AttendanceCaptureOutcome.incomplete);
    });

    test('retrieveLostData throwing counts as no photo, never crashes startup',
        () async {
      final h = harness(retrieveThrows: PlatformException(code: 'channel'));
      h.db.draft = draftFor();

      await recover(h.container);

      expect(h.db.rows, isEmpty);
      expect(notice(h.container)?.outcome, AttendanceCaptureOutcome.incomplete);
    });

    test('off Android, retrieveLostData is never called', () async {
      final h = harness(isAndroid: false);
      h.db.draft = draftFor();

      await recover(h.container);

      expect(h.retrieveCalls, isEmpty);
      expect(notice(h.container)?.outcome, AttendanceCaptureOutcome.incomplete);
    });

    test('signed out: does nothing and does not use up the one attempt',
        () async {
      final h = harness(signedInUser: null, lost: lostPhoto(cachedPhoto()));
      h.db.draft = draftFor();

      await recover(h.container);

      expect(h.retrieveCalls, isEmpty);
      expect(h.db.draft, isNotNull);

      // The same process then signs in: recovery still gets its one run.
      h.container.read(_signedInUserId.notifier).state = userId;
      await recover(h.container);

      expect(h.retrieveCalls, hasLength(1));
      expect(h.db.rows, hasLength(1));
    });

    test('normal return then restart: nothing to recover, nothing duplicated',
        () async {
      final h = harness();
      // Same-process capture completed normally…
      await captureWithDraft(
        db: h.db,
        draft: draftFor(operationId: 'op-normal'),
        captureSelfie: () async => 'attendance_selfies/x.jpg',
        enqueue: (r) => h.db.insert(userId, r),
      );
      // …then the app restarts. The picker cached nothing (its Dart call was
      // waiting), so retrieveLostData is empty.
      await recover(h.container);

      expect(h.db.rows, hasLength(1));
      expect(notice(h.container), isNull);
    });
  });
}
