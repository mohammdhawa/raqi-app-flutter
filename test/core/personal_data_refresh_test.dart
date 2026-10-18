import 'package:doc_approval/core/services/personal_data_refresh.dart';
import 'package:doc_approval/features/attendance/data/attendance_repository.dart';
import 'package:doc_approval/features/attendance/data/leave_repository.dart';
import 'package:doc_approval/features/attendance/domain/attendance_record.dart';
import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:doc_approval/features/attendance/presentation/providers/attendance_controller.dart';
import 'package:doc_approval/features/attendance/presentation/providers/leave_providers.dart';
import 'package:doc_approval/features/attendance/presentation/providers/month_attendance_providers.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:doc_approval/features/documents/data/documents_repository.dart';
import 'package:doc_approval/features/documents/domain/document.dart';
import 'package:doc_approval/features/home/domain/attention_items.dart';
import 'package:doc_approval/features/requests/presentation/providers/requests_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts every fetch, keyed by what asked for it.
final _calls = <String, int>{};
void _count(String key) => _calls[key] = (_calls[key] ?? 0) + 1;

class _LeaveRepo extends Fake implements LeaveRepository {
  @override
  Future<LeaveBalance> balance() async {
    _count('balance');
    return const LeaveBalance(
        year: 2026, allocatedDays: 21, usedDays: 0, remainingDays: 21);
  }

  @override
  Future<List<LeaveRequest>> myRequests({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
    int? perPage,
  }) async {
    // approvedLeaveTodayProvider asks for approved only; the list for all.
    _count(status == LeaveStatusFilter.approved ? 'leaveToday' : 'myLeaves');
    return const [];
  }

  @override
  Future<LeaveRequestsPage> myRequestsPage({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
    int? perPage,
    int page = 1,
  }) async {
    _count('monthLeaves');
    return (requests: const <LeaveRequest>[], hasMore: false);
  }

  @override
  Future<List<LeaveRequest>> approvals({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? perPage,
  }) async {
    _count('approvals');
    return const [];
  }
}

class _AttendanceRepo extends Fake implements AttendanceRepository {
  @override
  Future<AttendanceRecordsPage> myRecords({
    DateTime? date,
    DateTime? from,
    DateTime? to,
    bool? rejected,
    int page = 1,
  }) async {
    // The month view starts on the 1st; the 7-day window does not.
    _count(from?.day == 1 ? 'monthRecords' : 'recentRecords');
    return const AttendanceRecordsPage(
        records: [], currentPage: 1, lastPage: 1, total: 0);
  }
}

class _DocsRepo extends Fake implements DocumentsRepository {
  @override
  Future<DocumentsPage> list({
    required DocumentListType type,
    int page = 1,
    DocumentStatusFilter statusFilter = DocumentStatusFilter.all,
  }) async {
    _count(type == DocumentListType.sent ? 'sent' : 'awaiting');
    return const DocumentsPage(
        documents: [], currentPage: 1, lastPage: 1, total: 0);
  }
}

final _month = DateTime(2026, 10);

/// Mounts a scope over [user]'s data with every personal source alive, then
/// hands back a [WidgetRef] to refresh it with.
Future<WidgetRef> _mount(WidgetTester t, User user) async {
  _calls.clear();
  final c = ProviderContainer(overrides: [
    currentUserProvider.overrideWithValue(user),
    currentLocalDayProvider.overrideWithValue(DateTime(2026, 10, 18)),
    leaveRepositoryProvider.overrideWithValue(_LeaveRepo()),
    attendanceRepositoryProvider.overrideWithValue(_AttendanceRepo()),
    documentsRepositoryProvider.overrideWithValue(_DocsRepo()),
  ]);
  addTearDown(c.dispose);
  for (final p in <ProviderListenable<Object?>>[
    approvedLeaveTodayProvider,
    leaveBalanceProvider,
    recentRecordsProvider,
    monthRecordsProvider(_month),
    documentsAwaitingMeProvider,
    sentDocumentsProvider,
    myLeaveRequestsProvider,
    leaveApprovalsProvider,
  ]) {
    c.listen(p, (_, __) {});
  }
  late WidgetRef ref;
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: Consumer(builder: (_, r, __) {
      ref = r;
      return const SizedBox.shrink();
    }),
  ));
  await t.pumpAndSettle();
  return ref;
}

void main() {
  testWidgets('refetches every personal source once', (t) async {
    final ref = await _mount(t, const User(id: 3, name: 'م', role: 'manager'));
    final before = Map.of(_calls);
    expect(
        before.keys,
        containsAll(<String>[
          'balance',
          'leaveToday',
          'myLeaves',
          'monthLeaves',
          'approvals',
          'monthRecords',
          'recentRecords',
          'sent',
          'awaiting',
        ]));

    await refreshPersonalData(ref);
    await t.pumpAndSettle();

    for (final key in before.keys) {
      expect(_calls[key], before[key]! + 1, reason: key);
    }
  });

  testWidgets('a role-less user never refreshes approvals', (t) async {
    final ref = await _mount(t, const User(id: 7, name: 'x'));
    final approvalsBefore = _calls['approvals'];

    await refreshPersonalData(ref);
    await t.pumpAndSettle();

    expect(_calls['approvals'], approvalsBefore);
    expect(_calls['sent'], isNull, reason: 'no document role, no fetch');
    expect(_calls['awaiting'], isNull);
    expect(_calls['myLeaves'], 2);
    expect(_calls['balance'], 2);
  });

  testWidgets('sources nobody opened are not created', (t) async {
    _calls.clear();
    final c = ProviderContainer(overrides: [
      currentUserProvider
          .overrideWithValue(const User(id: 3, name: 'م', role: 'manager')),
      leaveRepositoryProvider.overrideWithValue(_LeaveRepo()),
      documentsRepositoryProvider.overrideWithValue(_DocsRepo()),
    ]);
    addTearDown(c.dispose);
    late WidgetRef ref;
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: Consumer(builder: (_, r, __) {
        ref = r;
        return const SizedBox.shrink();
      }),
    ));

    await refreshPersonalData(ref);
    await t.pumpAndSettle();

    expect(_calls, isEmpty);
  });
}
