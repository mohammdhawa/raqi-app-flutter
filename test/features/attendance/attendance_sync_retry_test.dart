import 'dart:io';

import 'package:doc_approval/features/attendance/data/attendance_local_db.dart';
import 'package:doc_approval/features/attendance/data/attendance_repository.dart';
import 'package:doc_approval/features/attendance/domain/attendance_record.dart';
import 'package:doc_approval/features/attendance/domain/pending_attendance_record.dart';
import 'package:doc_approval/features/attendance/presentation/providers/attendance_sync_service.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A business rule from ATTENDANCE_API.md §4 — permanent for that entry.
const _businessRuleError =
    'لا يمكن تسجيل الحضور في أيام العطلة (الجمعة والسبت).';

class _FakeLocalDb extends Fake implements AttendanceLocalDb {
  _FakeLocalDb(this.records);

  final List<PendingAttendanceRecord> records;
  final statuses = <int, AttendanceSyncStatus>{};
  final errors = <int, String?>{};

  @override
  Future<List<PendingAttendanceRecord>> getAll(int userId) async =>
      List.of(records);

  @override
  Future<List<PendingAttendanceRecord>> getUnsynced(int userId) async =>
      records.where((r) => r.isPending).toList();

  @override
  Future<void> updateStatus(
    int id,
    int userId, {
    required AttendanceSyncStatus status,
    String? errorMessage,
    bool clearError = false,
  }) async {
    statuses[id] = status;
    errors[id] = clearError ? null : errorMessage;
    // Mirror the write back into the queue so a later getUnsynced() reflects
    // it — a record left `pending` must come back around on the next attempt.
    for (var i = 0; i < records.length; i++) {
      if (records[i].id == id) {
        records[i] = records[i].copyWith(status: status);
      }
    }
  }
}

class _FakeAttendanceRepository extends Fake implements AttendanceRepository {
  final syncCalls = <List<PendingAttendanceRecord>>[];
  AttendanceSyncResult result =
      const AttendanceSyncResult(succeeded: [], failed: []);

  @override
  Future<AttendanceSyncResult> sync(
    List<PendingAttendanceRecord> entries,
  ) async {
    syncCalls.add(List.of(entries));
    return result;
  }
}

void main() {
  Directory tempDir(String prefix) {
    final dir = Directory.systemTemp.createTempSync(prefix);
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return dir;
  }

  File selfieFile(Directory dir, String name) =>
      File('${dir.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(const [1, 2, 3]);

  PendingAttendanceRecord pending({required int id, required String path}) =>
      PendingAttendanceRecord(
        id: id,
        type: AttendanceType.checkIn,
        latitude: 33.5,
        longitude: 36.3,
        selfiePath: path,
        recordedAt: DateTime(2026, 8, 18, 8, id),
      );

  ({
    ProviderContainer container,
    _FakeLocalDb db,
    _FakeAttendanceRepository repo
  }) harness(List<PendingAttendanceRecord> records) {
    final db = _FakeLocalDb(records);
    final repo = _FakeAttendanceRepository();
    final container = ProviderContainer(overrides: [
      attendanceLocalDbProvider.overrideWithValue(db),
      attendanceRepositoryProvider.overrideWithValue(repo),
      currentUserProvider
          .overrideWith((ref) => const User(id: 7, name: 'موظف')),
    ]);
    addTearDown(container.dispose);
    return (container: container, db: db, repo: repo);
  }

  group('AttendanceSyncFailure.isRetryable', () {
    test('the documented generic server failure is retryable', () {
      const failure = AttendanceSyncFailure(
        index: 0,
        error: attendanceSyncTransientError,
      );
      expect(failure.isRetryable, isTrue);
    });

    test('a business-rule message is terminal', () {
      const failure =
          AttendanceSyncFailure(index: 0, error: _businessRuleError);
      expect(failure.isRetryable, isFalse);
    });

    test('a missing selfie is a business rule, not a server failure', () {
      // The backend raises this as an AttendanceException, so it is user
      // copy and re-sending the same entry fails identically.
      const failure = AttendanceSyncFailure(
        index: 0,
        error: 'الصورة الشخصية مطلوبة لكل سجل.',
      );
      expect(failure.isRetryable, isFalse);
    });

    test('surrounding whitespace does not flip a retryable failure', () {
      const failure = AttendanceSyncFailure(
        index: 0,
        error: '  $attendanceSyncTransientError ',
      );
      expect(failure.isRetryable, isTrue);
    });
  });

  group('AttendanceSyncService.syncPending — failed[] is not all terminal', () {
    test('a transient server failure keeps the record queued for retry',
        () async {
      final dir = tempDir('selfies');
      final selfie = selfieFile(dir, 'a.jpg');
      final h = harness([pending(id: 1, path: selfie.path)]);
      h.repo.result = const AttendanceSyncResult(
        succeeded: [],
        failed: [
          AttendanceSyncFailure(
            index: 0,
            error: attendanceSyncTransientError,
          ),
        ],
      );

      await h.container.read(attendanceSyncServiceProvider).syncPending();

      // Not marked failed — `failed` is terminal in this app: it schedules no
      // retry and the only thing the user can do with the tile is dismiss it.
      expect(h.db.statuses.containsKey(1), isFalse);
      // Its selfie must survive, or the retry has nothing to upload.
      expect(selfie.existsSync(), isTrue);
    });

    test('a still-queued record is re-sent on the next attempt', () async {
      final dir = tempDir('selfies');
      final selfie = selfieFile(dir, 'a.jpg');
      final h = harness([pending(id: 1, path: selfie.path)]);
      h.repo.result = const AttendanceSyncResult(
        succeeded: [],
        failed: [
          AttendanceSyncFailure(
            index: 0,
            error: attendanceSyncTransientError,
          ),
        ],
      );

      final service = h.container.read(attendanceSyncServiceProvider);
      await service.syncPending();
      await service.syncPending();

      expect(h.repo.syncCalls, hasLength(2));
      expect(h.repo.syncCalls.last.single.id, 1);
    });

    test('a business-rule rejection is terminal and dismissible', () async {
      final dir = tempDir('selfies');
      final selfie = selfieFile(dir, 'a.jpg');
      final h = harness([pending(id: 1, path: selfie.path)]);
      h.repo.result = const AttendanceSyncResult(
        succeeded: [],
        failed: [AttendanceSyncFailure(index: 0, error: _businessRuleError)],
      );

      await h.container.read(attendanceSyncServiceProvider).syncPending();

      expect(h.db.statuses[1], AttendanceSyncStatus.failed);
      // The rule is shown verbatim so the employee learns why.
      expect(h.db.errors[1], _businessRuleError);
    });

    test('a mixed batch maps each index to the right record and outcome',
        () async {
      final dir = tempDir('selfies');
      final first = selfieFile(dir, 'first.jpg');
      final second = selfieFile(dir, 'second.jpg');
      final third = selfieFile(dir, 'third.jpg');
      final h = harness([
        pending(id: 1, path: first.path), // index 0 — succeeds
        pending(id: 2, path: second.path), // index 1 — business rule
        pending(id: 3, path: third.path), // index 2 — transient
      ]);
      h.repo.result = const AttendanceSyncResult(
        succeeded: [],
        failed: [
          AttendanceSyncFailure(index: 1, error: _businessRuleError),
          AttendanceSyncFailure(
            index: 2,
            error: attendanceSyncTransientError,
          ),
        ],
      );

      await h.container.read(attendanceSyncServiceProvider).syncPending();

      expect(h.db.statuses[1], AttendanceSyncStatus.synced);
      expect(h.db.statuses[2], AttendanceSyncStatus.failed);
      expect(h.db.statuses.containsKey(3), isFalse, reason: 'stays pending');

      // Only the synced record's selfie is reclaimed; the queued one keeps
      // the file it still has to upload.
      expect(first.existsSync(), isFalse);
      expect(third.existsSync(), isTrue);
    });

    test('indices are read against the sent batch, not the raw queue',
        () async {
      // A record whose selfie vanished is filtered out BEFORE the request, so
      // failed[].index counts positions in what was actually sent.
      final dir = tempDir('selfies');
      final valid = selfieFile(dir, 'valid.jpg');
      final h = harness([
        pending(id: 1, path: '${dir.path}${Platform.pathSeparator}gone.jpg'),
        pending(id: 2, path: valid.path),
      ]);
      h.repo.result = const AttendanceSyncResult(
        succeeded: [],
        failed: [
          AttendanceSyncFailure(
            index: 0,
            error: attendanceSyncTransientError,
          ),
        ],
      );

      await h.container.read(attendanceSyncServiceProvider).syncPending();

      // id 1 is the missing-selfie record: terminal, and unrelated to index 0.
      expect(h.db.statuses[1], AttendanceSyncStatus.failed);
      expect(h.db.errors[1], contains('لم تعد صورة التسجيل متوفرة'));
      // id 2 was the only entry sent, so index 0 is its transient failure.
      expect(h.db.statuses.containsKey(2), isFalse);
      expect(valid.existsSync(), isTrue);
    });
  });
}
