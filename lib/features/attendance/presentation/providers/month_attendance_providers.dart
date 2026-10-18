import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/attendance_repository.dart';
import '../../data/leave_repository.dart';
import '../../domain/attendance_record.dart';
import '../../domain/leave.dart';
import '../../domain/month_days.dart';
import 'attendance_controller.dart';
import 'attendance_queue_controller.dart';

/// What the server knows about one month: attendance rows and approved leave.
class MonthRecords {
  const MonthRecords({required this.records, required this.approvedLeaves});

  final List<AttendanceRecord> records;
  final List<LeaveRequest> approvedLeaves;
}

/// Pages through approved leave for [year] until the paginator says it is
/// done. `myRequests` returns only page 1, which would silently drop leaves.
Future<List<LeaveRequest>> _fetchApprovedLeaves(
  LeaveRepository repo,
  int year, {
  int maxPages = 10,
}) async {
  final all = <LeaveRequest>[];
  for (var page = 1; page <= maxPages; page++) {
    final result = await repo.myRequestsPage(
      status: LeaveStatusFilter.approved,
      year: year,
      page: page,
    );
    all.addAll(result.requests);
    if (!result.hasMore) break;
  }
  return all;
}

/// Server data for a month. The key is `DateTime(year, month)`.
final monthRecordsProvider =
    FutureProvider.autoDispose.family<MonthRecords, DateTime>((ref, month) async {
  final first = DateTime(month.year, month.month);
  final last = DateTime(month.year, month.month + 1, 0);
  final leaveRepo = ref.watch(leaveRepositoryProvider);

  final results = await Future.wait([
    fetchAllMyRecords(
      ref.watch(attendanceRepositoryProvider),
      from: first,
      to: last,
    ),
    _fetchApprovedLeaves(leaveRepo, month.year),
    // A leave that began in December can run into January.
    if (month.month == 1) _fetchApprovedLeaves(leaveRepo, month.year - 1),
  ]);

  final leaves = [
    for (final list in results.skip(1).cast<List<LeaveRequest>>()) ...list,
  ].where((l) {
    final start = DateTime(l.startDate.year, l.startDate.month, l.startDate.day);
    final end = DateTime(l.endDate.year, l.endDate.month, l.endDate.day);
    return !start.isAfter(last) && !end.isBefore(first);
  }).toList();

  return MonthRecords(
    records: results.first as List<AttendanceRecord>,
    approvedLeaves: leaves,
  );
});

/// The month's day entries: server data merged with the local offline queue.
final monthDaysProvider = Provider.autoDispose
    .family<AsyncValue<List<DayEntry>>, DateTime>((ref, month) {
  final today = ref.watch(currentLocalDayProvider);
  final queue = ref.watch(attendanceQueueProvider);
  return ref.watch(monthRecordsProvider(month)).whenData(
        (data) => deriveMonthDays(
          month: month,
          today: today,
          records: data.records,
          pending: queue,
          approvedLeaves: data.approvedLeaves,
        ),
      );
});
