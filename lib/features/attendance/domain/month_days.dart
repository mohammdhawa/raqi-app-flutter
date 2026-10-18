import '../../../shared/widgets/day_state.dart';
import '../data/attendance_repository.dart';
import 'attendance_record.dart';
import 'attendance_twins.dart';
import 'leave.dart';
import 'pending_attendance_record.dart';

/// One calendar day of a month, with the state derived for it and the rows
/// that justify that state.
class DayEntry {
  const DayEntry({
    required this.day,
    required this.state,
    this.records = const [],
    this.pending = const [],
    this.leave,
    this.worked = Duration.zero,
  });

  final DateTime day;
  final DayState state;
  final List<AttendanceRecord> records;
  final List<PendingAttendanceRecord> pending;
  final LeaveRequest? leave;

  /// Sum of `workHours` on the day's valid check-out rows.
  final Duration worked;
}

class MonthSummary {
  const MonthSummary({
    required this.presentDays,
    required this.worked,
    required this.incompleteDays,
    required this.rejectedDays,
    required this.leaveDays,
  });

  final int presentDays;
  final Duration worked;
  final int incompleteDays;
  final int rejectedDays;
  final int leaveDays;
}

DateTime _dayKey(DateTime d) {
  final l = d.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Derives one [DayEntry] per calendar day of [month].
///
/// Only the states the app can prove from its own data are produced
/// (present, incomplete, rejected, leave, pendingSync, noRecord, future);
/// late / absent / holiday need server data that does not exist yet and are
/// never guessed. First match wins:
/// 1. after [today] → future
/// 2. a still-pending local row with no remote twin → pendingSync
///    (synced rows stay in the queue but are not "awaiting sync")
/// 3. a valid check-in missing its checkout → incomplete
/// 4. a valid check-in → present
/// 5. an approved leave covering the day → leave
/// 6. only rejected remote rows or failed local rows → rejected
/// 7. otherwise → noRecord
List<DayEntry> deriveMonthDays({
  required DateTime month,
  required DateTime today,
  required List<AttendanceRecord> records,
  required List<PendingAttendanceRecord> pending,
  required List<LeaveRequest> approvedLeaves,
}) {
  final todayKey = _dayKey(today);
  final remoteByDay = <DateTime, List<AttendanceRecord>>{};
  for (final r in records) {
    remoteByDay.putIfAbsent(_dayKey(r.recordedAt), () => []).add(r);
  }
  final localByDay = <DateTime, List<PendingAttendanceRecord>>{};
  for (final p in pending) {
    localByDay.putIfAbsent(_dayKey(p.recordedAt), () => []).add(p);
  }

  final count = DateTime(month.year, month.month + 1, 0).day;
  return List.generate(count, (i) {
    final day = DateTime(month.year, month.month, i + 1);
    final dayRecords = remoteByDay[day] ?? const <AttendanceRecord>[];
    final dayLocal = localByDay[day] ?? const <PendingAttendanceRecord>[];

    final valid = dayRecords.where((r) => !r.isRejected).toList();
    final validCheckIns =
        valid.where((r) => r.type == AttendanceType.checkIn).toList();
    final worked = valid
        .where((r) => r.type == AttendanceType.checkOut)
        .fold<Duration>(
          Duration.zero,
          (sum, r) =>
              sum + Duration(minutes: ((r.workHours ?? 0) * 60).round()),
        );

    LeaveRequest? leave;
    for (final l in approvedLeaves) {
      if (l.isApproved && l.coversDate(day)) {
        leave = l;
        break;
      }
    }

    final DayState state;
    if (day.isAfter(todayKey)) {
      state = DayState.future;
    } else if (dayLocal.any(
      (p) => p.status == AttendanceSyncStatus.pending &&
          !hasRemoteTwin(p, dayRecords),
    )) {
      state = DayState.pendingSync;
    } else if (validCheckIns.any((r) => r.isMissingCheckout)) {
      state = DayState.incomplete;
    } else if (validCheckIns.isNotEmpty) {
      state = DayState.present;
    } else if (leave != null) {
      state = DayState.leave;
    } else if (dayRecords.any((r) => r.isRejected) ||
        dayLocal.any((p) => p.isFailed)) {
      state = DayState.rejected;
    } else {
      state = DayState.noRecord;
    }

    return DayEntry(
      day: day,
      state: state,
      records: dayRecords,
      pending: dayLocal,
      leave: leave,
      worked: worked,
    );
  });
}

MonthSummary summarizeMonth(List<DayEntry> days) {
  int count(DayState s) => days.where((d) => d.state == s).length;
  return MonthSummary(
    presentDays: count(DayState.present),
    worked: days.fold(Duration.zero, (sum, d) => sum + d.worked),
    incompleteDays: count(DayState.incomplete),
    rejectedDays: count(DayState.rejected),
    leaveDays: count(DayState.leave),
  );
}

/// Every record in `[from, to]`, following the paginator to its end.
/// [maxPages] bounds a misbehaving server.
Future<List<AttendanceRecord>> fetchAllMyRecords(
  AttendanceRepository repo, {
  required DateTime from,
  required DateTime to,
  int maxPages = 20,
}) async {
  final all = <AttendanceRecord>[];
  for (var page = 1; page <= maxPages; page++) {
    final result = await repo.myRecords(from: from, to: to, page: page);
    all.addAll(result.records);
    if (!result.hasMore) break;
  }
  return all;
}
