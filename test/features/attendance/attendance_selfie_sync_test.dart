import 'dart:io';

import 'package:doc_approval/core/errors/api_failure.dart';
import 'package:doc_approval/features/attendance/data/attendance_local_db.dart';
import 'package:doc_approval/features/attendance/data/attendance_repository.dart';
import 'package:doc_approval/features/attendance/data/selfie_storage.dart';
import 'package:doc_approval/features/attendance/domain/attendance_record.dart';
import 'package:doc_approval/features/attendance/domain/pending_attendance_record.dart';
import 'package:doc_approval/features/attendance/presentation/providers/attendance_sync_service.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  }
}

class _FakeAttendanceRepository extends Fake implements AttendanceRepository {
  final syncCalls = <List<PendingAttendanceRecord>>[];
  AttendanceSyncResult result =
      const AttendanceSyncResult(succeeded: [], failed: []);

  /// When set, [sync] throws this instead of returning [result].
  Object? throwOnSync;

  @override
  Future<AttendanceSyncResult> sync(
    List<PendingAttendanceRecord> entries,
  ) async {
    syncCalls.add(List.of(entries));
    final err = throwOnSync;
    if (err != null) throw err;
    return result;
  }
}

void main() {
  PendingAttendanceRecord pending({required int id, required String path}) {
    return PendingAttendanceRecord(
      id: id,
      type: AttendanceType.checkIn,
      latitude: 33.5,
      longitude: 36.3,
      selfiePath: path,
      recordedAt: DateTime(2026, 7, 8, 8, id),
    );
  }

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

  ({ProviderContainer container, _FakeLocalDb db, _FakeAttendanceRepository repo})
      harness(List<PendingAttendanceRecord> records) {
    final db = _FakeLocalDb(records);
    final repo = _FakeAttendanceRepository();
    final container = ProviderContainer(overrides: [
      attendanceLocalDbProvider.overrideWithValue(db),
      attendanceRepositoryProvider.overrideWithValue(repo),
      currentUserProvider.overrideWith(
        (ref) => const User(id: 7, name: 'موظف'),
      ),
    ]);
    addTearDown(container.dispose);
    return (container: container, db: db, repo: repo);
  }

  group('selfie storage', () {
    test('persist copies the selfie and stores a path relative to app-support',
        () async {
      final cacheDir = tempDir('selfie_cache');
      final supportDir = tempDir('app_support');
      final source = selfieFile(cacheDir, 'picked.jpg');

      final persisted =
          await persistSelfieForUpload(source, baseDir: supportDir);

      // Stored RELATIVE, not absolute — survives an iOS container-UUID change.
      expect(persisted, isNot(source.path));
      expect(persisted, startsWith('attendance_selfies'));
      expect(persisted, isNot(startsWith(supportDir.path)));
      expect(persisted, endsWith('.jpg'));
      // Resolves to the real copied file against the current support dir.
      final resolved = await resolveSelfiePath(persisted, baseDir: supportDir);
      expect(resolved, startsWith(supportDir.path));
      expect(File(resolved).readAsBytesSync(), const [1, 2, 3]);
      // Copy, not move — the cache original is left for the OS to clean.
      expect(source.existsSync(), isTrue);
    });

    test('resolveSelfiePath joins a relative path but passes absolute through',
        () async {
      final supportDir = tempDir('app_support');

      final resolved = await resolveSelfiePath(
        'attendance_selfies/x.jpg',
        baseDir: supportDir,
      );
      expect(resolved, startsWith(supportDir.path));
      expect(resolved, endsWith('x.jpg'));

      // Legacy rows (and any absolute path) are returned unchanged.
      const abs = '/data/app/attendance_selfies/y.jpg';
      expect(await resolveSelfiePath(abs, baseDir: supportDir), abs);
    });

    test('sweep deletes only files no queue row references', () async {
      final supportDir = tempDir('app_support');
      final selfiesDir = Directory(
        '${supportDir.path}${Platform.pathSeparator}attendance_selfies',
      )..createSync(recursive: true);
      final keep = File(
        '${selfiesDir.path}${Platform.pathSeparator}keep.jpg',
      )..writeAsBytesSync(const [1]);
      final orphan = File(
        '${selfiesDir.path}${Platform.pathSeparator}orphan.jpg',
      )..writeAsBytesSync(const [2]);

      await sweepOrphanedSelfieFiles({'keep.jpg'}, baseDir: supportDir);

      expect(keep.existsSync(), isTrue);
      expect(orphan.existsSync(), isFalse);
    });
  });

  group('AttendanceSyncService.syncPending', () {
    test('missing selfie is marked failed while a sibling still uploads',
        () async {
      final dir = tempDir('selfies');
      final valid = selfieFile(dir, 'valid.jpg');
      // The missing-file record comes FIRST so a mapping bug (indices taken
      // against the unfiltered list) would misattribute the result.
      final records = [
        pending(id: 1, path: '${dir.path}${Platform.pathSeparator}gone.jpg'),
        pending(id: 2, path: valid.path),
      ];
      final h = harness(records);

      await h.container.read(attendanceSyncServiceProvider).syncPending();

      expect(h.db.statuses[1], AttendanceSyncStatus.failed);
      expect(h.db.errors[1], contains('لم تعد صورة التسجيل متوفرة'));
      expect(h.db.statuses[2], AttendanceSyncStatus.synced);
      expect(h.repo.syncCalls, hasLength(1));
      expect(h.repo.syncCalls.single.map((r) => r.id), [2]);
      // The synced record's persisted selfie is cleaned up.
      expect(valid.existsSync(), isFalse);
    });

    test('server failure indices map against the filtered batch', () async {
      final dir = tempDir('selfies');
      final first = selfieFile(dir, 'first.jpg');
      final second = selfieFile(dir, 'second.jpg');
      final records = [
        pending(id: 1, path: '${dir.path}${Platform.pathSeparator}gone.jpg'),
        pending(id: 2, path: first.path),
        pending(id: 3, path: second.path),
      ];
      final h = harness(records);
      // Index 0 of the SENT batch is record id 2 (id 1 was filtered out).
      h.repo.result = const AttendanceSyncResult(
        succeeded: [],
        failed: [AttendanceSyncFailure(index: 0, error: 'سجل مرفوض')],
      );

      await h.container.read(attendanceSyncServiceProvider).syncPending();

      expect(h.db.statuses[1], AttendanceSyncStatus.failed);
      expect(h.db.statuses[2], AttendanceSyncStatus.failed);
      expect(h.db.errors[2], 'سجل مرفوض');
      expect(h.db.statuses[3], AttendanceSyncStatus.synced);
      // Server-rejected records keep their selfie until dismissed.
      expect(first.existsSync(), isTrue);
      expect(second.existsSync(), isFalse);
    });

    test('makes no network call when every pending selfie is missing',
        () async {
      final dir = tempDir('selfies');
      final records = [
        pending(id: 1, path: '${dir.path}${Platform.pathSeparator}gone.jpg'),
      ];
      final h = harness(records);

      await h.container.read(attendanceSyncServiceProvider).syncPending();

      expect(h.repo.syncCalls, isEmpty);
      expect(h.db.statuses[1], AttendanceSyncStatus.failed);
    });

    test('non-transient rejection marks the batch dismissible-failed',
        () async {
      final dir = tempDir('selfies');
      final valid = selfieFile(dir, 'valid.jpg');
      final h = harness([pending(id: 1, path: valid.path)]);
      // 413/400/422 will fail identically on every retry — must not wedge.
      h.repo.throwOnSync = ApiFailure(
        code: ApiErrorCode.unknown,
        message: 'Payload too large',
        statusCode: 413,
      );

      await h.container.read(attendanceSyncServiceProvider).syncPending();

      expect(h.db.statuses[1], AttendanceSyncStatus.failed);
      expect(h.db.errors[1], contains('رفض الخادم'));
      // Kept until the user dismisses it.
      expect(valid.existsSync(), isTrue);
    });

    test('auth failure leaves records pending (recoverable, not failed)',
        () async {
      final dir = tempDir('selfies');
      final valid = selfieFile(dir, 'valid.jpg');
      final h = harness([pending(id: 1, path: valid.path)]);
      h.repo.throwOnSync = ApiFailure(
        code: ApiErrorCode.unauthenticated,
        message: 'Session expired',
        statusCode: 401,
      );

      await h.container.read(attendanceSyncServiceProvider).syncPending();

      // Still pending → will re-send after re-login, not terminally failed.
      expect(h.db.statuses.containsKey(1), isFalse);
    });
  });
}
