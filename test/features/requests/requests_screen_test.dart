import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:doc_approval/features/attendance/presentation/providers/leave_providers.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:doc_approval/features/requests/domain/request_item.dart';
import 'package:doc_approval/features/requests/presentation/providers/requests_providers.dart';
import 'package:doc_approval/features/requests/presentation/screens/requests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

const _employee = User(id: 7, name: 'x');
const _manager = User(id: 3, name: 'm', role: 'manager');

RequestItem _item(
  int id,
  RequestStatus status, {
  RequestKind kind = RequestKind.document,
  String? requester,
}) =>
    RequestItem(
      kind: kind,
      id: id,
      title: 'طلب رقم $id',
      subtitle: 'تفاصيل $id',
      status: status,
      stepLabel: 'خطوة $id',
      sortDate: DateTime(2026, 10, 18).subtract(Duration(days: id)),
      route: '/documents/$id',
      requesterName: requester,
    );

List<Override> _overrides({
  User user = _employee,
  List<RequestItem> mine = const [],
  List<RequestItem> inbox = const [],
}) =>
    [
      currentUserProvider.overrideWithValue(user),
      myRequestsFeedProvider.overrideWithValue(AsyncData(mine)),
      inboxFeedProvider.overrideWithValue(AsyncData(inbox)),
      pendingDecisionsCountProvider.overrideWithValue(inbox.length),
      leaveBalanceProvider.overrideWith((ref) async => const LeaveBalance(
          year: 2026, allocatedDays: 14, usedDays: 0, remainingDays: 14)),
    ];

void main() {
  testWidgets('role-less user sees no inbox segment and no document option',
      (t) async {
    await pumpTestApp(t, const RequestsScreen(), overrides: _overrides());
    expect(find.text('بانتظار قراري'), findsNothing);
    await t.tap(find.text('طلب جديد'));
    await t.pumpAndSettle();
    expect(find.text('مستند من قالب'), findsNothing);
    expect(find.text('أنواع أخرى من الطلبات الإدارية ستتوفر قريباً.'),
        findsOneWidget);
    await t.tap(find.text('إجازة'));
    await t.pumpAndSettle();
    expect(find.text('route:/attendance/leave/new'), findsOneWidget);
  });

  testWidgets('manager can start a document from a template', (t) async {
    await pumpTestApp(t, const RequestsScreen(),
        overrides: _overrides(user: _manager));
    await t.tap(find.text('طلب جديد'));
    await t.pumpAndSettle();
    await t.tap(find.text('مستند من قالب'));
    await t.pumpAndSettle();
    expect(find.text('route:/documents/new'), findsOneWidget);
  });

  testWidgets('manager sees the inbox count and opens on inbox when asked',
      (t) async {
    await pumpTestApp(t, const RequestsScreen(openInbox: true),
        overrides: _overrides(
          user: _manager,
          inbox: [
            _item(1, RequestStatus.pending, requester: 'سارة'),
            _item(2, RequestStatus.pending, requester: 'خالد'),
          ],
        ));
    expect(find.text('بانتظار قراري'), findsOneWidget);
    // Exact badge text, wrapped in the LTR isolate marks.
    expect(find.text(' (⁦2⁩)'), findsOneWidget);
    expect(find.text('طلبات تنتظر قرارك.'), findsOneWidget);
    expect(find.text('سارة'), findsOneWidget);
    expect(find.text('خالد'), findsOneWidget);
  });

  testWidgets('no count badge when the inbox is empty', (t) async {
    await pumpTestApp(t, const RequestsScreen(),
        overrides: _overrides(user: _manager));
    expect(find.text('بانتظار قراري'), findsOneWidget);
    expect(find.textContaining('('), findsNothing);
  });

  testWidgets('inbox segment can be switched to and from', (t) async {
    await pumpTestApp(t, const RequestsScreen(),
        overrides: _overrides(
          user: _manager,
          mine: [_item(1, RequestStatus.approved)],
          inbox: [_item(2, RequestStatus.pending, requester: 'سارة')],
        ));
    expect(find.text('طلب رقم 1'), findsOneWidget);
    expect(find.text('سارة'), findsNothing);
    await t.tap(find.text('بانتظار قراري'));
    await t.pumpAndSettle();
    expect(find.text('سارة'), findsOneWidget);
    expect(find.text('طلب رقم 1'), findsNothing);
    await t.tap(find.text('طلباتي'));
    await t.pumpAndSettle();
    expect(find.text('طلب رقم 1'), findsOneWidget);
  });

  testWidgets('tapping a request opens its route', (t) async {
    await pumpTestApp(t, const RequestsScreen(),
        overrides: _overrides(mine: [_item(9, RequestStatus.pending)]));
    await t.tap(find.text('طلب رقم 9'));
    await t.pumpAndSettle();
    expect(find.text('route:/documents/9'), findsOneWidget);
  });

  testWidgets('filter chips narrow the list', (t) async {
    await pumpTestApp(t, const RequestsScreen(),
        overrides: _overrides(mine: [
          _item(1, RequestStatus.pending),
          _item(2, RequestStatus.approved),
          _item(3, RequestStatus.rejected),
        ]));
    expect(find.text('طلب رقم 1'), findsOneWidget);
    expect(find.text('طلب رقم 2'), findsOneWidget);
    expect(find.text('طلب رقم 3'), findsOneWidget);
    await t.tap(find.text('مرفوضة'));
    await t.pumpAndSettle();
    expect(find.text('طلب رقم 1'), findsNothing);
    expect(find.text('طلب رقم 2'), findsNothing);
    expect(find.text('طلب رقم 3'), findsOneWidget);
    await t.tap(find.text('الكل'));
    await t.pumpAndSettle();
    expect(find.text('طلب رقم 1'), findsOneWidget);
  });

  testWidgets('every card pairs its status text with an icon', (t) async {
    await pumpTestApp(t, const RequestsScreen(),
        overrides: _overrides(mine: [_item(1, RequestStatus.rejected)]));
    expect(find.text('مرفوض'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('shows the annual balance chip', (t) async {
    await pumpTestApp(t, const RequestsScreen(), overrides: _overrides());
    expect(find.text('سنوية'), findsOneWidget);
    expect(find.textContaining('14'), findsOneWidget);
    expect(find.textContaining('يوماً'), findsOneWidget);
  });

  testWidgets('empty feeds show their own message', (t) async {
    await pumpTestApp(t, const RequestsScreen(),
        overrides: _overrides(user: _manager));
    expect(find.text('لا توجد طلبات بعد'), findsOneWidget);
    await t.tap(find.text('بانتظار قراري'));
    await t.pumpAndSettle();
    expect(find.text('لا يوجد ما ينتظر قرارك'), findsOneWidget);
  });
}
