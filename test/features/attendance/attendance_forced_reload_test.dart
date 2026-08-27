import 'dart:async';

import 'package:doc_approval/features/attendance/data/attendance_local_db.dart';
import 'package:doc_approval/features/attendance/data/attendance_repository.dart';
import 'package:doc_approval/features/attendance/domain/attendance_record.dart';
import 'package:doc_approval/features/attendance/domain/pending_attendance_record.dart';
import 'package:doc_approval/features/attendance/presentation/providers/attendance_controller.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLocalDb extends Fake implements AttendanceLocalDb {
  @override
  Future<List<PendingAttendanceRecord>> getAll(int userId) async => const [];
}

/// Hands out one manually-completed fetch at a time, so a reload can be fired
/// while an earlier fetch is still on the wire.
class _BlockingAttendanceRepository extends Fake
    implements AttendanceRepository {
  final List<Completer<AttendanceRecordsPage>> pending = [];

  int get callCount => pending.length;

  @override
  Future<AttendanceRecordsPage> myRecords({
    DateTime? date,
    DateTime? from,
    DateTime? to,
    bool? rejected,
    int page = 1,
  }) {
    final completer = Completer<AttendanceRecordsPage>();
    pending.add(completer);
    return completer.future;
  }

  void completeLast(AttendanceRecordsPage page) => pending.last.complete(page);
}

AttendanceRecordsPage _page(List<AttendanceRecord> records) =>
    AttendanceRecordsPage(
      records: records,
      currentPage: 1,
      lastPage: 1,
      total: records.length,
    );

AttendanceRecord _record({
  required int id,
  required DateTime recordedAt,
  bool isRejected = false,
}) =>
    AttendanceRecord(
      id: id,
      userId: 7,
      type: AttendanceType.checkIn,
      latitude: 33.5,
      longitude: 36.3,
      recordedAt: recordedAt,
      createdAt: recordedAt,
      isRejected: isRejected,
      rejectionReason: isRejected ? 'location' : null,
    );

void main() {
  // An HR refusal happens on the server, on today's date, while the app is
  // doing something else. The reload it triggers cannot be folded into a
  // fetch that was already in flight: that response was requested BEFORE the
  // refusal and cannot contain it. Dropping it leaves a refused check-in
  // driving the button, so the employee is told to record the day again and
  // then cannot.
  test('a forced reload during an in-flight fetch is re-run, not dropped',
      () async {
    final now = DateTime.now();
    final repo = _BlockingAttendanceRepository();

    final container = ProviderContainer(overrides: [
      attendanceLocalDbProvider.overrideWithValue(_FakeLocalDb()),
      attendanceRepositoryProvider.overrideWithValue(repo),
      currentUserProvider.overrideWith((ref) => const User(id: 7, name: 'موظف')),
    ]);
    addTearDown(container.dispose);

    // The controller's own bootstrap is now in flight and unanswered.
    final controller = container.read(attendanceControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    expect(repo.callCount, 1);

    // The refusal notification lands while that fetch is still open.
    await controller.reload();
    expect(repo.callCount, 1, reason: 'still coalesced behind the first fetch');

    // The in-flight response predates the refusal: it still shows the
    // check-in as valid.
    repo.completeLast(_page([_record(id: 1, recordedAt: now)]));
    await Future<void>.delayed(Duration.zero);

    // The queued reload must now have gone out on its own.
    expect(repo.callCount, 2, reason: 'the forced reload was dropped');

    repo.completeLast(
      _page([_record(id: 1, recordedAt: now, isRejected: true)]),
    );
    await Future<void>.delayed(Duration.zero);

    // And its answer is what governs: no valid record, so the screen offers
    // «تسجيل حضور» again.
    expect(container.read(attendanceStatusProvider), isNull);
  });

  test('several forced reloads during one fetch collapse into a single re-run',
      () async {
    final now = DateTime.now();
    final repo = _BlockingAttendanceRepository();

    final container = ProviderContainer(overrides: [
      attendanceLocalDbProvider.overrideWithValue(_FakeLocalDb()),
      attendanceRepositoryProvider.overrideWithValue(repo),
      currentUserProvider.overrideWith((ref) => const User(id: 7, name: 'موظف')),
    ]);
    addTearDown(container.dispose);

    final controller = container.read(attendanceControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    await controller.reload();
    await controller.reload();
    await controller.reload();

    repo.completeLast(_page([_record(id: 1, recordedAt: now)]));
    await Future<void>.delayed(Duration.zero);

    expect(repo.callCount, 2);

    repo.completeLast(_page(const []));
    await Future<void>.delayed(Duration.zero);

    // The follow-up settles the flag; nothing keeps firing afterwards.
    expect(repo.callCount, 2);
  });

  // The day guard still does its job for ordinary refreshes — an unforced
  // refresh within the same day must not produce a second request.
  test('an unforced refresh on the same day is still coalesced', () async {
    final now = DateTime.now();
    final repo = _BlockingAttendanceRepository();

    final container = ProviderContainer(overrides: [
      attendanceLocalDbProvider.overrideWithValue(_FakeLocalDb()),
      attendanceRepositoryProvider.overrideWithValue(repo),
      currentUserProvider.overrideWith((ref) => const User(id: 7, name: 'موظف')),
    ]);
    addTearDown(container.dispose);

    final controller = container.read(attendanceControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    repo.completeLast(_page([_record(id: 1, recordedAt: now)]));
    await Future<void>.delayed(Duration.zero);
    expect(repo.callCount, 1);

    await controller.refreshToday();
    await Future<void>.delayed(Duration.zero);

    expect(repo.callCount, 1);
  });
}
