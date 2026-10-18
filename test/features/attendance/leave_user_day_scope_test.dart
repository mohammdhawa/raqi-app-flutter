import 'package:doc_approval/features/attendance/data/leave_repository.dart';
import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:doc_approval/features/attendance/presentation/providers/attendance_controller.dart';
import 'package:doc_approval/features/attendance/presentation/providers/leave_providers.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every listing with one request whose id is the id of the user
/// signed in at the moment of the call, so a test can tell whose data a
/// controller holds.
class _PerUserLeaveRepository extends Fake implements LeaveRepository {
  _PerUserLeaveRepository(this.whoAsks);

  final int? Function() whoAsks;
  int myRequestsCalls = 0;
  int approvalsCalls = 0;

  LeaveRequest _row() => LeaveRequest(
        id: whoAsks() ?? 0,
        startDate: DateTime(2026, 10, 18),
        endDate: DateTime(2026, 10, 18),
        status: LeaveStatus.pending,
      );

  @override
  Future<List<LeaveRequest>> myRequests({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
    int? perPage,
  }) async {
    myRequestsCalls++;
    return [_row()];
  }

  @override
  Future<List<LeaveRequest>> approvals({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? perPage,
  }) async {
    approvalsCalls++;
    return [_row()];
  }
}

/// One approved leave on 18 October 2026.
class _LeaveOnThe18th extends Fake implements LeaveRepository {
  int calls = 0;

  @override
  Future<List<LeaveRequest>> myRequests({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
    int? perPage,
  }) async {
    calls++;
    return [
      LeaveRequest(
        id: 1,
        startDate: DateTime(2026, 10, 18),
        endDate: DateTime(2026, 10, 18),
        status: LeaveStatus.approved,
      ),
    ];
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('approvedLeaveTodayProvider', () {
    // The app stays alive across midnight; yesterday's leave must not keep
    // the hero on «إجازة» this morning.
    test('rolls over with the local day', () async {
      final day = StateProvider<DateTime>((ref) => DateTime(2026, 10, 18));
      final repo = _LeaveOnThe18th();
      final c = ProviderContainer(overrides: [
        leaveRepositoryProvider.overrideWithValue(repo),
        currentLocalDayProvider.overrideWith((ref) => ref.watch(day)),
      ]);
      addTearDown(c.dispose);
      c.listen(approvedLeaveTodayProvider, (_, __) {});

      expect((await c.read(approvedLeaveTodayProvider.future))?.id, 1);

      c.read(day.notifier).state = DateTime(2026, 10, 19);
      expect(await c.read(approvedLeaveTodayProvider.future), isNull);
      expect(repo.calls, 2, reason: 'the new day is looked up afresh');
    });
  });

  group('leave list controllers are scoped to the signed-in user', () {
    final user = StateProvider<User?>(
        (ref) => const User(id: 1, name: 'الأول', role: 'manager'));

    ProviderContainer containerWith(_PerUserLeaveRepository Function(
            ProviderContainer Function() c)
        build) {
      late final ProviderContainer c;
      final repo = build(() => c);
      c = ProviderContainer(overrides: [
        leaveRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWith((ref) => ref.watch(user)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    // Shared device: the next person to sign in must not be shown the
    // previous account's requests from memory.
    test('my requests reload for a new user', () async {
      late _PerUserLeaveRepository repo;
      final c = containerWith((c) =>
          repo = _PerUserLeaveRepository(() => c().read(user)?.id));
      c.listen(myLeaveRequestsProvider, (_, __) {});
      await _settle();
      final first = c.read(myLeaveRequestsProvider.notifier);
      expect(c.read(myLeaveRequestsProvider).requests.single.id, 1);

      c.read(user.notifier).state = const User(id: 2, name: 'الثاني');
      c.read(myLeaveRequestsProvider);
      await _settle();

      expect(c.read(myLeaveRequestsProvider.notifier), isNot(same(first)));
      expect(repo.myRequestsCalls, 2);
      expect(c.read(myLeaveRequestsProvider).requests.single.id, 2);
    });

    test('approvals reload for a new user', () async {
      late _PerUserLeaveRepository repo;
      final c = containerWith((c) =>
          repo = _PerUserLeaveRepository(() => c().read(user)?.id));
      c.listen(leaveApprovalsProvider, (_, __) {});
      await _settle();
      final first = c.read(leaveApprovalsProvider.notifier);
      expect(c.read(leaveApprovalsProvider).requests.single.id, 1);

      c.read(user.notifier).state =
          const User(id: 2, name: 'الثاني', role: 'chief');
      c.read(leaveApprovalsProvider);
      await _settle();

      expect(c.read(leaveApprovalsProvider.notifier), isNot(same(first)));
      expect(repo.approvalsCalls, 2);
      expect(c.read(leaveApprovalsProvider).requests.single.id, 2);
    });
  });
}
