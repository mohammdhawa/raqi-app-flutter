import 'package:doc_approval/features/attendance/data/attendance_repository.dart';
import 'package:doc_approval/features/attendance/domain/attendance_record.dart';
import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:doc_approval/features/attendance/domain/month_days.dart';
import 'package:doc_approval/features/attendance/domain/pending_attendance_record.dart';
import 'package:doc_approval/features/attendance/presentation/widgets/month_calendar.dart';
import 'package:doc_approval/shared/widgets/day_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

int _id = 0;

AttendanceRecord checkIn(DateTime at,
        {bool rejected = false, bool missingCheckout = false}) =>
    AttendanceRecord(
      id: ++_id,
      userId: 7,
      type: AttendanceType.checkIn,
      latitude: 0,
      longitude: 0,
      recordedAt: at,
      createdAt: at,
      isRejected: rejected,
      status: missingCheckout ? 'missing_checkout' : null,
    );

AttendanceRecord checkOut(DateTime at, {double? workHours}) => AttendanceRecord(
      id: ++_id,
      userId: 7,
      type: AttendanceType.checkOut,
      latitude: 0,
      longitude: 0,
      recordedAt: at,
      createdAt: at,
      workHours: workHours,
    );

PendingAttendanceRecord local(DateTime at,
        {AttendanceSyncStatus status = AttendanceSyncStatus.pending}) =>
    PendingAttendanceRecord(
      type: AttendanceType.checkIn,
      latitude: 0,
      longitude: 0,
      selfiePath: 'x.jpg',
      recordedAt: at,
      status: status,
    );

LeaveRequest leave(DateTime from, DateTime to) => LeaveRequest(
      id: 1,
      startDate: from,
      endDate: to,
      status: LeaveStatus.approved,
    );

class _FakeRepo extends Fake implements AttendanceRepository {
  final requestedPages = <int>[];
  int get totalRecords => 3;

  @override
  Future<AttendanceRecordsPage> myRecords({
    DateTime? date,
    DateTime? from,
    DateTime? to,
    bool? rejected,
    int page = 1,
  }) async {
    requestedPages.add(page);
    final at = DateTime(2026, 10, page);
    return AttendanceRecordsPage(
      records: page == 1
          ? [checkIn(at), checkOut(at)]
          : [checkIn(at)],
      currentPage: page,
      lastPage: 2,
      total: totalRecords,
    );
  }
}

void main() {
  final month = DateTime(2026, 10);
  final today = DateTime(2026, 10, 18);

  List<DayEntry> derive({
    DateTime? now,
    List<AttendanceRecord> records = const [],
    List<PendingAttendanceRecord> pending = const [],
    List<LeaveRequest> leaves = const [],
  }) =>
      deriveMonthDays(
        month: month,
        today: now ?? today,
        records: records,
        pending: pending,
        approvedLeaves: leaves,
      );

  test('one entry per day, future after today', () {
    final days = derive();
    expect(days, hasLength(31));
    expect(days[17].state, DayState.noRecord);
    expect(days[18].state, DayState.future);
  });

  test('rejected and missing-checkout records do not count', () {
    final days = derive(records: [
      checkIn(DateTime(2026, 10, 5, 8), rejected: true),
      checkIn(DateTime(2026, 10, 6, 8), missingCheckout: true),
      checkIn(DateTime(2026, 10, 7, 8)),
      checkOut(DateTime(2026, 10, 7, 16), workHours: 8.0),
    ]);
    expect(days[4].state, DayState.rejected);
    expect(days[5].state, DayState.incomplete);
    expect(days[6].state, DayState.present);
    final s = summarizeMonth(days);
    expect(s.presentDays, 1);
    expect(s.incompleteDays, 1);
    expect(s.rejectedDays, 1);
    expect(s.worked, const Duration(hours: 8));
  });

  test('pending local record wins over noRecord', () {
    final days = derive(pending: [local(DateTime(2026, 10, 18, 8))]);
    expect(days[17].state, DayState.pendingSync);
  });

  test('synced and failed local rows are not awaiting sync', () {
    final days = derive(pending: [
      local(DateTime(2026, 10, 10, 8), status: AttendanceSyncStatus.synced),
      local(DateTime(2026, 10, 11, 8), status: AttendanceSyncStatus.failed),
    ]);
    // Synced: confirmed by the server, so a valid check-in (not pendingSync).
    expect(days[9].state, DayState.present);
    expect(days[10].state, DayState.rejected);
  });

  // The server confirmed the capture; only the month fetch is stale. The hero
  // already says present, so the calendar and the month tile must agree.
  test('a synced local check-in with no remote row counts as present', () {
    final days = derive(
      pending: [local(DateTime(2026, 10, 18, 8), status: AttendanceSyncStatus.synced)],
    );
    expect(days[17].state, DayState.present);
    expect(summarizeMonth(days).presentDays, 1);
  });

  test('a synced local check-out adds no worked time', () {
    final days = derive(pending: [
      local(DateTime(2026, 10, 18, 8), status: AttendanceSyncStatus.synced),
      PendingAttendanceRecord(
        type: AttendanceType.checkOut,
        latitude: 0,
        longitude: 0,
        selfiePath: 'y.jpg',
        recordedAt: DateTime(2026, 10, 18, 16),
        status: AttendanceSyncStatus.synced,
      ),
    ]);
    expect(days[17].state, DayState.present);
    expect(days[17].worked, Duration.zero);
  });

  testWidgets('the day sheet lists a synced capture the fetch has not seen',
      (t) async {
    final entry = derive(
      pending: [local(DateTime(2026, 10, 18, 8), status: AttendanceSyncStatus.synced)],
    )[17];
    await pumpTestApp(
      t,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDaySheet(context, entry),
          child: const Text('open'),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('لا يوجد تسجيل لهذا اليوم.'), findsNothing);
    expect(find.textContaining('حضور'), findsWidgets);
    expect(find.text('مؤكد'), findsOne);
  });

  test('a synced local twin does not mask the server row', () {
    final days = derive(
      records: [checkIn(DateTime(2026, 10, 8, 8, 0, 30))],
      pending: [local(DateTime(2026, 10, 8, 8))],
    );
    expect(days[7].state, DayState.present);
  });

  test('approved leave shows as leave unless attended', () {
    final days = derive(
      leaves: [leave(DateTime(2026, 10, 11), DateTime(2026, 10, 12))],
      records: [
        checkIn(DateTime(2026, 10, 12, 8)),
        checkOut(DateTime(2026, 10, 12, 16), workHours: 8),
      ],
    );
    expect(days[10].state, DayState.leave);
    expect(days[11].state, DayState.present);
    expect(summarizeMonth(days).leaveDays, 1);
  });

  test('today boundary', () {
    final days = derive(
      now: DateTime(2026, 10, 19),
      records: [checkIn(DateTime(2026, 10, 19, 0, 5))],
    );
    expect(days[18].state, DayState.present);
    expect(days[19].state, DayState.future);
  });

  test('fetchAllMyRecords follows pagination', () async {
    final repo = _FakeRepo();
    final all = await fetchAllMyRecords(repo,
        from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));
    expect(all, hasLength(repo.totalRecords));
    expect(repo.requestedPages, [1, 2]);
  });
}
