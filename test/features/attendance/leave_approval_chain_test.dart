import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:doc_approval/core/network/api_client.dart';
import 'package:doc_approval/core/services/push_notification_service.dart';
import 'package:doc_approval/features/attendance/data/leave_repository.dart';
import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:doc_approval/features/attendance/presentation/providers/leave_providers.dart';
import 'package:doc_approval/features/attendance/presentation/screens/leave_request_form_screen.dart';
import 'package:doc_approval/features/attendance/presentation/widgets/leave_request_tile.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:doc_approval/features/notifications/domain/notification_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode({
        'leave_request': {
          'id': 44,
          'start_date': '2026-09-01',
          'end_date': '2026-09-03',
          'status': 'pending',
          'leave_type_id': 2,
          'current_approver_id': 7,
          'can_review': false,
          'approvals': const [],
        },
      }),
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeApiClient extends Fake implements ApiClient {
  _FakeApiClient(HttpClientAdapter adapter) {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.invalid/api',
        validateStatus: (_) => true,
      ),
    )..httpClientAdapter = adapter;
  }

  late final Dio _dio;

  @override
  Dio get dio => _dio;
}

void main() {
  group('LeaveRepository.create', () {
    test('sends the ordered approver_ids contract without manager_id',
        () async {
      final adapter = _RecordingAdapter();
      final repository = LeaveRepository(_FakeApiClient(adapter));

      final created = await repository.create(
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 3),
        approverIds: const [7, 12, 3],
        leaveTypeId: 2,
        reason: 'سبب',
      );

      final request = adapter.lastRequest!;
      expect(request.method, 'POST');
      expect(request.path, '/attendance/leave-requests');
      expect(request.data, isA<Map<String, dynamic>>());
      final data = request.data as Map<String, dynamic>;
      expect(data['approver_ids'], [7, 12, 3]);
      expect(data.containsKey('manager_id'), isFalse);
      expect(data['leave_type_id'], 2);
      expect(data.containsKey('leave_type'), isFalse);
      expect(created.id, 44);
    });

    test('managers() asks for a page big enough to reach the chief', () async {
      // The endpoint paginates at 25 by default, ordered `name asc`, and the
      // picker has neither a search box nor a load-more — so a roster of 25
      // managers plus the single chief left the chief on page two and
      // unselectable. Nothing about that is visible in the UI, hence the guard
      // sits on the request itself.
      final adapter = _RecordingAdapter();
      final repository = LeaveRepository(_FakeApiClient(adapter));

      await repository.managers();

      final request = adapter.lastRequest!;
      expect(request.path, '/attendance/leave-managers');
      expect(
        request.queryParameters['per_page'],
        LeaveRepository.maxPerPage,
      );
    });
  });

  group('leave notification routing', () {
    test('both sequential event payloads expose the leave request id', () {
      for (final type in const [
        'leave_request_approval_required',
        'leave_request_approval_reassigned',
      ]) {
        final data = {
          'type': type,
          'leave_request_id': '42',
          'approval_order': '2',
        };

        expect(PushNotificationService.leaveRequestIdFrom(data), 42);
        expect(NotificationType.fromString(type), NotificationType.leave);
      }
    });

    test('id parsing remains tolerant of numeric FCM test payloads', () {
      expect(
        PushNotificationService.leaveRequestIdFrom(
          {'leave_request_id': 19.0},
        ),
        19,
      );
      expect(PushNotificationService.leaveRequestIdFrom(const {}), isNull);
    });
  });

  group('leave approval chain UI', () {
    testWidgets('the form keeps managers and chief in visible selection order',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith(
              (ref) => const User(id: 99, name: 'الموظف'),
            ),
            leaveManagersProvider.overrideWith(
              (ref) async => const [
                LeaveManager(id: 7, name: 'المدير الأول'),
                LeaveManager(id: 12, name: 'المدير الثاني'),
                LeaveManager(id: 3, name: 'الرئيس'),
              ],
            ),
            leaveTypesProvider.overrideWith((ref) async => const []),
            leaveBalanceProvider.overrideWith(
              (ref) async => const LeaveBalance(
                year: 2026,
                allocatedDays: 21,
                usedDays: 0,
                remainingDays: 21,
              ),
            ),
          ],
          child: const MaterialApp(home: LeaveRequestFormScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final addButton = find.byKey(const Key('add-leave-approver'));
      await tester.ensureVisible(addButton);
      await tester.pumpAndSettle();
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // One sheet, ticked in order — the chief included, since a leave chain
      // is commonly closed by them and the picker must not filter them out
      // the way the document forms deliberately do.
      for (final name in const [
        'المدير الأول',
        'المدير الثاني',
        'الرئيس',
      ]) {
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('confirm-approver-selection')));
      await tester.pumpAndSettle();

      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
      expect(
        find.text('3 من 10 — اسحب المقبض لتغيير ترتيب الموافقة.'),
        findsOneWidget,
      );
      expect(find.text('الرئيس'), findsOneWidget);

      // Exercise the actual drag callback, not merely the presence of handles:
      // moving row 1 below row 2 changes the visible decision order.
      final firstRow = find.byKey(const ValueKey('leave-approver-7'));
      final secondRow = find.byKey(const ValueKey('leave-approver-12'));
      await tester.ensureVisible(firstRow);
      await tester.pumpAndSettle();
      await tester.drag(
        find.descendant(
          of: firstRow,
          matching: find.byIcon(Icons.drag_handle),
        ),
        const Offset(0, 130),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(firstRow).dy,
        greaterThan(tester.getTopLeft(secondRow).dy),
      );
    });

    testWidgets('a pending tile shows the current step and total',
        (tester) async {
      final request = LeaveRequest(
        id: 8,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 3),
        status: LeaveStatus.pending,
        managerId: 12,
        managerName: 'المدير الثاني',
        currentApproverId: 12,
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
          LeaveApprovalStep(
            userId: 3,
            userName: 'الرئيس',
            approvalOrder: 3,
            status: LeaveApprovalStatus.pending,
          ),
        ],
        days: 3,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: LeaveRequestTile(request: request, onTap: () {}),
            ),
          ),
        ),
      );

      expect(find.text('بانتظار: المدير الثاني · 2 / 3'), findsOneWidget);
    });
  });
}
