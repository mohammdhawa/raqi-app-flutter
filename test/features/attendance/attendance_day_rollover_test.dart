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

class _FakeAttendanceRepository extends Fake implements AttendanceRepository {
  _FakeAttendanceRepository(this.page);

  final AttendanceRecordsPage page;

  @override
  Future<AttendanceRecordsPage> myRecords({
    DateTime? date,
    DateTime? from,
    DateTime? to,
    int page = 1,
  }) async =>
      this.page;
}

void main() {
  test('day rollover drops yesterday\'s records from status and today list',
      () async {
    // Anchored to the real clock because AttendanceController's bootstrap
    // filters with DateTime.now(); the rollover itself is then driven by
    // overriding currentLocalDayProvider, not by waiting for midnight.
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final repo = _FakeAttendanceRepository(
      AttendanceRecordsPage(
        records: [
          AttendanceRecord(
            id: 1,
            userId: 7,
            type: AttendanceType.checkIn,
            latitude: 33.5,
            longitude: 36.3,
            recordedAt: now,
            createdAt: now,
          ),
        ],
        currentPage: 1,
        lastPage: 1,
        total: 1,
      ),
    );

    final dayOverride = StateProvider<DateTime>((ref) => todayStart);
    final container = ProviderContainer(overrides: [
      attendanceLocalDbProvider.overrideWithValue(_FakeLocalDb()),
      attendanceRepositoryProvider.overrideWithValue(repo),
      currentUserProvider.overrideWith((ref) => const User(id: 7, name: 'موظف')),
      currentLocalDayProvider.overrideWith((ref) => ref.watch(dayOverride)),
    ]);
    addTearDown(container.dispose);

    // Instantiate the controller and let its bootstrap fetch complete.
    container.read(attendanceControllerProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(attendanceStatusProvider), AttendanceType.checkIn);
    expect(container.read(todayAttendanceProvider), hasLength(1));

    // Midnight passes: the day provider emits the next day and both
    // day-scoped providers must recompute off the same cached records.
    container.read(dayOverride.notifier).state =
        todayStart.add(const Duration(days: 1));

    expect(container.read(attendanceStatusProvider), isNull);
    expect(container.read(todayAttendanceProvider), isEmpty);
  });
}
