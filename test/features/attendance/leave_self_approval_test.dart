import 'package:doc_approval/features/attendance/data/leave_repository.dart';
import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:doc_approval/features/attendance/presentation/providers/leave_providers.dart';
import 'package:doc_approval/features/attendance/presentation/screens/leave_request_detail_screen.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLeaveRepository extends Fake implements LeaveRepository {
  _FakeLeaveRepository({
    this.managersResult = const [],
    this.approvalsResult = const [],
  });

  final List<LeaveManager> managersResult;
  final List<LeaveRequest> approvalsResult;

  @override
  Future<List<LeaveManager>> managers() async => managersResult;

  @override
  Future<List<LeaveRequest>> approvals({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? perPage,
  }) async =>
      approvalsResult;

  @override
  Future<List<LeaveRequest>> myRequests({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
    int? perPage,
  }) async =>
      const [];

  // The detail screen resolves through the paged variants when the loaded
  // lists miss, so a fake that only answers the list calls would blow up on
  // the first cold open.
  @override
  Future<LeaveRequestsPage> approvalsPage({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? perPage,
    int page = 1,
  }) async =>
      (
        requests: page == 1 ? approvalsResult : const <LeaveRequest>[],
        hasMore: false,
      );

  @override
  Future<LeaveRequestsPage> myRequestsPage({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
    int? perPage,
    int page = 1,
  }) async =>
      (requests: const <LeaveRequest>[], hasMore: false);
}

void main() {
  LeaveRequest request({
    required int id,
    required int requesterId,
    required int managerId,
    LeaveStatus status = LeaveStatus.pending,
  }) =>
      LeaveRequest(
        id: id,
        startDate: DateTime(2026, 8, 20),
        endDate: DateTime(2026, 8, 21),
        status: status,
        requesterId: requesterId,
        requesterName: 'مقدّم الطلب',
        managerId: managerId,
        managerName: 'المدير',
        days: 2,
      );

  group('leaveManagersProvider', () {
    test('drops the authenticated user from the approver list', () async {
      // `/attendance/leave-managers` is a company-wide roster, so a manager
      // or the chief finds themselves in it. Naming yourself is refused by
      // the backend (422 on manager_id), so it must not be offerable.
      final container = ProviderContainer(overrides: [
        leaveRepositoryProvider.overrideWithValue(
          _FakeLeaveRepository(managersResult: const [
            LeaveManager(id: 7, name: 'أنا'),
            LeaveManager(id: 9, name: 'مدير آخر'),
            LeaveManager(id: 11, name: 'الرئيس'),
          ]),
        ),
        currentUserProvider.overrideWith(
          (ref) => const User(id: 7, name: 'أنا'),
        ),
      ]);
      addTearDown(container.dispose);

      final managers = await container.read(leaveManagersProvider.future);

      expect(managers.map((m) => m.id), [9, 11]);
      expect(managers.any((m) => m.id == 7), isFalse);
    });

    test('keeps the whole roster when nobody is signed in', () async {
      final container = ProviderContainer(overrides: [
        leaveRepositoryProvider.overrideWithValue(
          _FakeLeaveRepository(managersResult: const [
            LeaveManager(id: 9, name: 'مدير'),
          ]),
        ),
        currentUserProvider.overrideWith((ref) => null),
      ]);
      addTearDown(container.dispose);

      expect(await container.read(leaveManagersProvider.future), hasLength(1));
    });
  });

  group('legacy self-assigned leave request', () {
    Future<void> pumpDetail(
      WidgetTester tester, {
      required LeaveRequest leaveRequest,
      required int currentUserId,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            leaveRepositoryProvider.overrideWithValue(
              _FakeLeaveRepository(approvalsResult: [leaveRequest]),
            ),
            currentUserProvider.overrideWith(
              (ref) => User(id: currentUserId, name: 'مراجع'),
            ),
          ],
          child: MaterialApp(
            home: LeaveRequestDetailScreen(leaveRequestId: leaveRequest.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('approve is withdrawn but reject stays available',
        (tester) async {
      // The backend refuses to APPROVE a row whose manager_id == user_id
      // whenever it was created, but deliberately leaves REJECT open so the
      // row is not stranded behind a gate nobody can pass.
      await pumpDetail(
        tester,
        leaveRequest: request(id: 1, requesterId: 7, managerId: 7),
        currentUserId: 7,
      );

      expect(find.byKey(const Key('leave-approve-button')), findsNothing);
      expect(find.text('رفض'), findsOneWidget);
      expect(
        find.byKey(const Key('leave-self-approval-notice')),
        findsOneWidget,
      );
    });

    testWidgets('the notice explains why approval is unavailable',
        (tester) async {
      await pumpDetail(
        tester,
        leaveRequest: request(id: 1, requesterId: 7, managerId: 7),
        currentUserId: 7,
      );

      expect(
        find.textContaining('لا يمكن اعتماد طلب إجازة مقدَّمه هو نفسه معتمِده'),
        findsOneWidget,
      );
    });

    testWidgets('an ordinary request keeps both actions', (tester) async {
      await pumpDetail(
        tester,
        leaveRequest: request(id: 1, requesterId: 3, managerId: 7),
        currentUserId: 7,
      );

      expect(find.byKey(const Key('leave-approve-button')), findsOneWidget);
      expect(find.text('رفض'), findsOneWidget);
      expect(find.byKey(const Key('leave-self-approval-notice')), findsNothing);
    });

    testWidgets('somebody who is not the named approver gets no actions',
        (tester) async {
      await pumpDetail(
        tester,
        leaveRequest: request(id: 1, requesterId: 3, managerId: 9),
        currentUserId: 7,
      );

      expect(find.byKey(const Key('leave-approve-button')), findsNothing);
      expect(find.text('رفض'), findsNothing);
    });
  });
}
