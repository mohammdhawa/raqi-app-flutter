import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:doc_approval/features/documents/domain/document.dart';
import 'package:doc_approval/features/requests/domain/request_item.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> step(int order, String name, String status) => {
      'user_id': order + 100,
      'user_name': name,
      'approval_order': order,
      'status': status,
    };

LeaveRequest leaveFixture({
  required String status,
  List<Map<String, dynamic>> approvals = const [],
  String start = '2026-10-04',
  String end = '2026-10-06',
  bool isExcuse = false,
  Map<String, dynamic>? manager,
}) =>
    LeaveRequest.fromJson({
      'id': 5,
      'start_date': start,
      'end_date': end,
      'status': status,
      'days': 3,
      'is_excuse': isExcuse,
      'approvals': approvals,
      if (manager != null) 'manager': manager,
      'created_at': '2026-10-01T08:00:00',
    });

Map<String, dynamic> wf(int id, int order, String role, String status) => {
      'id': id,
      'user_id': id,
      'order': order,
      'role': role,
      'status': status,
      'user': {'id': id, 'name': 'مستخدم $id'},
    };

Document docFixture({
  String status = 'pending',
  String mode = 'sequential',
  List<int> nextPending = const [],
  List<Map<String, dynamic>> workflows = const [],
}) =>
    Document.fromJson(
      {
        'id': 9,
        'title': 'تقرير',
        'status': status,
        'workflow_mode': mode,
        'created_at': '2026-10-02T10:00:00',
        'creator': {'id': 1, 'name': 'منشئ'},
        'workflows': workflows,
      },
      nextPendingUsers: [
        for (final id in nextPending) _user(id),
      ],
    );

dynamic _user(int id) => Document.fromJson({
      'id': 0,
      'title': '',
      'created_at': '2026-10-02T10:00:00',
      'workflows': [wf(id, 1, 'manager', 'pending')],
    }).workflows.single.user;

RequestItem itemAt(DateTime d, RequestKind k) => RequestItem(
      kind: k,
      id: 1,
      title: 't',
      subtitle: 's',
      status: RequestStatus.pending,
      sortDate: d,
      route: '/',
    );

void main() {
  test('leave pending step names the current approver', () {
    final r = leaveFixture(status: 'pending', approvals: [
      step(1, 'رامي العلي', 'approved'),
      step(2, 'هالة منصور', 'pending'),
    ]);
    final i = requestFromLeave(r, typeLabel: 'إجازة مرضية');
    expect(i.title, 'إجازة مرضية');
    expect(i.stepLabel, 'الخطوة 2 من 2 · بانتظار هالة منصور');
    expect(i.status, RequestStatus.pending);
    expect(i.route, '/attendance/leave/requests/${r.id}');
    expect(i.subtitle, contains('–'));
  });

  test('cancelled leave is not pending', () {
    expect(requestFromLeave(leaveFixture(status: 'cancelled')).status,
        RequestStatus.cancelled);
  });

  test('leave without a chain falls back to the manager, then to approved', () {
    expect(
      requestFromLeave(leaveFixture(status: 'pending', manager: {
        'id': 3,
        'name': 'سعد',
      })).stepLabel,
      'بانتظار سعد',
    );
    expect(requestFromLeave(leaveFixture(status: 'approved')).stepLabel,
        'اكتمل المسار');
    expect(
        requestFromLeave(leaveFixture(status: 'rejected')).stepLabel, isNull);
    expect(
        requestFromLeave(leaveFixture(status: 'approved', isExcuse: true))
            .stepLabel,
        'سجّلتها الموارد البشرية');
  });

  test('single-day leave drops the range', () {
    final i = requestFromLeave(leaveFixture(
        status: 'approved', start: '2026-10-04', end: '2026-10-04'));
    expect(i.subtitle, isNot(contains('–')));
  });

  test('document awaiting me only when I am a next pending user', () {
    expect(isAwaitingUser(docFixture(nextPending: [7]), 7), isTrue);
    expect(isAwaitingUser(docFixture(nextPending: [8]), 7), isFalse);
    expect(isAwaitingUser(docFixture(status: 'approved', nextPending: [7]), 7),
        isFalse);
  });

  group('nextPendingApprovers from list-endpoint workflows', () {
    final managers = [
      wf(1, 1, 'manager', 'pending'),
      wf(2, 2, 'manager', 'pending'),
      wf(3, 3, 'chief', 'pending'),
    ];

    test('sequential returns only the lowest-order manager', () {
      final d = docFixture(workflows: managers);
      expect(nextPendingApprovers(d).map((u) => u.id), [1]);
      expect(isAwaitingUser(d, 1), isTrue);
      expect(isAwaitingUser(d, 2), isFalse);
    });

    test('parallel returns every pending manager', () {
      final d = docFixture(mode: 'parallel', workflows: managers);
      expect(nextPendingApprovers(d).map((u) => u.id), [1, 2]);
    });

    test('with no pending managers it returns the chief', () {
      final d = docFixture(workflows: [
        wf(1, 1, 'manager', 'approved'),
        wf(3, 3, 'chief', 'pending'),
      ]);
      expect(nextPendingApprovers(d).map((u) => u.id), [3]);
    });

    test('a non-pending document returns nobody', () {
      expect(
          nextPendingApprovers(
              docFixture(status: 'approved', workflows: managers)),
          isEmpty);
    });

    test('the step label names those approvers', () {
      final i = requestFromDocument(docFixture(workflows: managers));
      expect(i.stepLabel, 'بانتظار مستخدم 1');
      expect(i.route, '/documents/9');
    });
  });

  test('merge cuts leave items older than unloaded documents', () {
    final merged = mergeRequests(
      [
        itemAt(DateTime(2026, 9, 1), RequestKind.leave),
        itemAt(DateTime(2026, 10, 10), RequestKind.leave),
      ],
      [itemAt(DateTime(2026, 10, 1), RequestKind.document)],
      documentsHaveMore: true,
    );
    expect(merged.map((e) => e.sortDate),
        [DateTime(2026, 10, 10), DateTime(2026, 10, 1)]);
  });

  test('merge keeps everything when no documents remain unloaded', () {
    final merged = mergeRequests(
      [itemAt(DateTime(2026, 9, 1), RequestKind.leave)],
      [itemAt(DateTime(2026, 10, 1), RequestKind.document)],
      documentsHaveMore: false,
    );
    expect(merged, hasLength(2));
  });
}
