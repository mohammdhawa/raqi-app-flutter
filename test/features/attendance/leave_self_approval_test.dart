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
    List<LeaveApprovalStep> approvals = const [],
    int? currentApproverId,
    bool? canReview,
    String managerName = 'المدير',
  }) =>
      LeaveRequest(
        id: id,
        startDate: DateTime(2026, 8, 20),
        endDate: DateTime(2026, 8, 21),
        status: status,
        requesterId: requesterId,
        requesterName: 'مقدّم الطلب',
        managerId: managerId,
        managerName: managerName,
        approvals: approvals,
        currentApproverId: currentApproverId,
        canReview: canReview,
        days: 2,
      );

  group('leaveManagersProvider', () {
    test('drops the authenticated user from the approver list', () async {
      // `/attendance/leave-managers` is a company-wide roster, so a manager
      // or the chief finds themselves in it. Naming yourself is refused by
      // the backend (422 on the matching approver_ids.N), so it must not be
      // offerable.
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

  group('sequential leave review', () {
    const steps = [
      LeaveApprovalStep(
        userId: 7,
        userName: 'المدير الأول',
        approvalOrder: 1,
        status: LeaveApprovalStatus.pending,
      ),
      LeaveApprovalStep(
        userId: 12,
        userName: 'المدير الثاني',
        approvalOrder: 2,
        status: LeaveApprovalStatus.pending,
      ),
      LeaveApprovalStep(
        userId: 3,
        userName: 'الرئيس',
        approvalOrder: 3,
        status: LeaveApprovalStatus.pending,
      ),
    ];

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

    testWidgets('a later approver sees disabled actions and the current name',
        (tester) async {
      await pumpDetail(
        tester,
        leaveRequest: request(
          id: 20,
          requesterId: 2,
          managerId: 7,
          managerName: 'المدير الأول',
          approvals: steps,
          currentApproverId: 7,
          canReview: false,
        ),
        currentUserId: 12,
      );

      expect(find.byKey(const Key('leave-waiting-action-bar')), findsOneWidget);
      expect(
        find.byKey(const Key('leave-approve-button-disabled')),
        findsOneWidget,
      );
      expect(find.textContaining('بانتظار موافقة المدير الأول'), findsWidgets);
      expect(find.byKey(const Key('leave-approve-button')), findsNothing);
    });

    testWidgets('server can_review false overrides a matching manager id',
        (tester) async {
      await pumpDetail(
        tester,
        leaveRequest: request(
          id: 21,
          requesterId: 2,
          managerId: 7,
          approvals: steps,
          currentApproverId: 7,
          canReview: false,
        ),
        currentUserId: 7,
      );

      expect(find.byKey(const Key('leave-waiting-action-bar')), findsOneWidget);
      expect(find.byKey(const Key('leave-approve-button')), findsNothing);
    });

    testWidgets('server can_review true enables the current approver',
        (tester) async {
      await pumpDetail(
        tester,
        leaveRequest: request(
          id: 22,
          requesterId: 2,
          managerId: 12,
          managerName: 'المدير الثاني',
          approvals: const [
            LeaveApprovalStep(
              userId: 7,
              userName: 'المدير الأول',
              approvalOrder: 1,
              status: LeaveApprovalStatus.approved,
            ),
            LeaveApprovalStep(
              userId: 12,
              userName: 'المدير الثاني',
              approvalOrder: 2,
              status: LeaveApprovalStatus.pending,
            ),
          ],
          currentApproverId: 12,
          canReview: true,
        ),
        currentUserId: 12,
      );

      expect(find.byKey(const Key('leave-approve-button')), findsOneWidget);
      expect(find.byKey(const Key('leave-reject-button')), findsOneWidget);
      expect(find.byKey(const Key('leave-waiting-action-bar')), findsNothing);
      expect(find.textContaining('بانتظار موافقة المدير الثاني'), findsNothing);
    });

    testWidgets('an approver who already acted is not promised a later turn',
        (tester) async {
      // The approvals queue hands the request back to EVERY approver on it, so
      // step 1 keeps reaching this screen while step 2 decides. Their step is
      // closed: no disabled bar saying the actions arrive "when the request
      // reaches you", because it never will. The body banner still names who
      // holds it now.
      await pumpDetail(
        tester,
        leaveRequest: request(
          id: 25,
          requesterId: 2,
          managerId: 12,
          managerName: 'المدير الثاني',
          approvals: const [
            LeaveApprovalStep(
              userId: 7,
              userName: 'المدير الأول',
              approvalOrder: 1,
              status: LeaveApprovalStatus.approved,
            ),
            LeaveApprovalStep(
              userId: 12,
              userName: 'المدير الثاني',
              approvalOrder: 2,
              status: LeaveApprovalStatus.pending,
            ),
          ],
          currentApproverId: 12,
          canReview: false,
        ),
        currentUserId: 7,
      );

      expect(find.byKey(const Key('leave-waiting-action-bar')), findsNothing);
      expect(find.byKey(const Key('leave-approve-button')), findsNothing);
      expect(find.textContaining('ستتاح الإجراءات'), findsNothing);
      expect(find.text('بانتظار موافقة المدير الثاني'), findsOneWidget);
    });

    testWidgets('a skipped approver on a still-pending row gets no action bar',
        (tester) async {
      // A reassignment closes the old holder's step while the request stays
      // pending on somebody else — the same closed-step case, reached without
      // the viewer ever having made a decision.
      await pumpDetail(
        tester,
        leaveRequest: request(
          id: 26,
          requesterId: 2,
          managerId: 12,
          managerName: 'المدير الثاني',
          approvals: const [
            LeaveApprovalStep(
              userId: 7,
              userName: 'المدير الأول',
              approvalOrder: 1,
              status: LeaveApprovalStatus.skipped,
            ),
            LeaveApprovalStep(
              userId: 12,
              userName: 'المدير الثاني',
              approvalOrder: 2,
              status: LeaveApprovalStatus.pending,
            ),
          ],
          currentApproverId: 12,
          canReview: false,
        ),
        currentUserId: 7,
      );

      expect(find.byKey(const Key('leave-waiting-action-bar')), findsNothing);
      expect(find.textContaining('ستتاح الإجراءات'), findsNothing);
    });

    testWidgets('the waiting viewer is told who holds the request only once',
        (tester) async {
      await pumpDetail(
        tester,
        leaveRequest: request(
          id: 27,
          requesterId: 2,
          managerId: 7,
          managerName: 'المدير الأول',
          approvals: steps,
          currentApproverId: 7,
          canReview: false,
        ),
        currentUserId: 12,
      );

      // The action bar carries the sentence; the body banner stands aside so
      // the same line does not appear twice on one screen.
      expect(find.byKey(const Key('leave-waiting-action-bar')), findsOneWidget);
      expect(
        find.textContaining('بانتظار موافقة المدير الأول'),
        findsOneWidget,
      );
    });

    testWidgets('the requester still sees who holds their pending request',
        (tester) async {
      await pumpDetail(
        tester,
        leaveRequest: request(
          id: 28,
          requesterId: 2,
          managerId: 7,
          managerName: 'المدير الأول',
          approvals: steps,
          currentApproverId: 7,
          canReview: false,
        ),
        currentUserId: 2,
      );

      expect(find.text('بانتظار موافقة المدير الأول'), findsOneWidget);
      expect(find.byKey(const Key('leave-waiting-action-bar')), findsNothing);
    });

    testWidgets('a rejected chain renders later steps as skipped',
        (tester) async {
      await pumpDetail(
        tester,
        leaveRequest: request(
          id: 23,
          requesterId: 2,
          managerId: 12,
          status: LeaveStatus.rejected,
          approvals: const [
            LeaveApprovalStep(
              userId: 7,
              userName: 'المدير الأول',
              approvalOrder: 1,
              status: LeaveApprovalStatus.approved,
            ),
            LeaveApprovalStep(
              userId: 12,
              userName: 'المدير الثاني',
              approvalOrder: 2,
              status: LeaveApprovalStatus.rejected,
            ),
            LeaveApprovalStep(
              userId: 3,
              userName: 'الرئيس',
              approvalOrder: 3,
              status: LeaveApprovalStatus.skipped,
            ),
          ],
          canReview: false,
        ),
        currentUserId: 3,
      );

      expect(find.text('تم تجاوزها'), findsOneWidget);
      expect(find.byKey(const Key('leave-waiting-action-bar')), findsNothing);
      expect(find.byKey(const Key('leave-approve-button')), findsNothing);
    });

    testWidgets('an HR excuse still has no approval workflow', (tester) async {
      await pumpDetail(
        tester,
        leaveRequest: LeaveRequest(
          id: 24,
          startDate: DateTime(2026, 8, 20),
          endDate: DateTime(2026, 8, 20),
          status: LeaveStatus.approved,
          isExcuse: true,
          days: 1,
        ),
        currentUserId: 7,
      );

      expect(find.text('عذر مسجّل من الموارد البشرية'), findsOneWidget);
      expect(find.text('سلسلة الموافقة'), findsNothing);
      expect(find.byKey(const Key('leave-waiting-action-bar')), findsNothing);
      expect(find.byKey(const Key('leave-approve-button')), findsNothing);
    });
  });
}
