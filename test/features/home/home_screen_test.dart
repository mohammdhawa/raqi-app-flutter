import 'package:doc_approval/features/attendance/domain/attendance_action.dart';
import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:doc_approval/features/attendance/domain/month_days.dart';
import 'package:doc_approval/features/attendance/presentation/providers/attendance_controller.dart';
import 'package:doc_approval/features/attendance/presentation/providers/leave_providers.dart';
import 'package:doc_approval/features/attendance/presentation/providers/month_attendance_providers.dart';
import 'package:doc_approval/features/attendance/presentation/widgets/hero_today_card.dart';
import 'package:doc_approval/features/attendance/domain/attendance_record.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:doc_approval/features/home/domain/attention_items.dart';
import 'package:doc_approval/features/home/presentation/home_screen.dart';
import 'package:doc_approval/features/notifications/presentation/providers/notifications_controller.dart';
import 'package:doc_approval/features/requests/domain/request_item.dart';
import 'package:doc_approval/features/requests/presentation/providers/requests_providers.dart';
import 'package:doc_approval/shared/widgets/day_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

final _today = DateTime(2026, 10, 18);
final _month = DateTime(2026, 10);

const _employee = User(id: 7, name: 'أحمد علي', departmentName: 'المبيعات');
const _manager = User(id: 3, name: 'منى خالد', role: 'manager');

RequestItem _inbox(int id) => RequestItem(
      kind: RequestKind.document,
      id: id,
      title: 'مستند $id',
      subtitle: 'تفاصيل',
      status: RequestStatus.pending,
      sortDate: DateTime(2026, 10, 18).subtract(Duration(days: id)),
      route: '/documents/$id',
      requesterName: 'مقدّم $id',
    );

List<DayEntry> _days() => List.generate(31, (i) {
      final day = DateTime(2026, 10, i + 1);
      if (day.day == 7 || day.day == 8) {
        return DayEntry(
          day: day,
          state: DayState.present,
          worked: const Duration(hours: 8, minutes: 30),
        );
      }
      return DayEntry(
          day: day,
          state: day.isAfter(_today) ? DayState.future : DayState.noRecord);
    });

List<Override> _overrides({
  User user = _employee,
  List<RequestItem> inbox = const [],
  Object? balanceError,
  List<AttentionItem> attention = const [],
}) =>
    [
      currentUserProvider.overrideWithValue(user),
      currentLocalDayProvider.overrideWithValue(_today),
      unreadCountProvider.overrideWithValue(0),
      leaveBalanceProvider.overrideWith((ref) async {
        if (balanceError != null) throw balanceError;
        return const LeaveBalance(
            year: 2026, allocatedDays: 21, usedDays: 6, remainingDays: 15);
      }),
      monthDaysProvider(_month).overrideWithValue(AsyncData(_days())),
      attentionItemsProvider.overrideWithValue(attention),
      inboxFeedProvider.overrideWithValue(AsyncData(inbox)),
      pendingDecisionsCountProvider.overrideWithValue(inbox.length),
      heroTodayModelProvider.overrideWithValue(
          const HeroTodayModel(phase: HeroPhase.notCheckedIn)),
      attendanceActionProvider.overrideWithValue(
          const AttendanceAction(nextType: AttendanceType.checkIn)),
      attendanceCapturingProvider.overrideWithValue(false),
    ];

Future<void> _pump(WidgetTester t, List<Override> overrides) async {
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await pumpTestApp(t, const HomeScreen(), overrides: overrides);
}

void main() {
  testWidgets('role-less home has no pending-decisions or team card',
      (t) async {
    await _pump(t, _overrides());
    expect(find.text('بانتظار قراري'), findsNothing);
    expect(find.textContaining('فريقي اليوم'), findsNothing);
    expect(find.text('الرواتب · ستتوفر قريباً'), findsOne);
    expect(find.text('أحمد علي'), findsOne);
    expect(find.text('المبيعات'), findsOne);
    expect(find.text('أع'), findsOne);
    expect(find.text('15'), findsOne);
    expect(find.text('2'), findsOne); // present days
    expect(find.textContaining('17:00'), findsOne); // worked hours
    expect(find.text('يحتاج انتباهك'), findsNothing);
  });

  testWidgets('manager home shows count and team placeholder', (t) async {
    await _pump(t, _overrides(user: _manager, inbox: [_inbox(1), _inbox(2)]));
    expect(find.text('بانتظار قراري'), findsOne);
    expect(find.text('2'), findsWidgets);
    expect(find.text('فريقي اليوم · ستتوفر قريباً'), findsOne);
    expect(find.text('مستند 1'), findsOne);
    await t.tap(find.text('عرض كل الطلبات'));
    await t.pumpAndSettle();
    expect(find.text('route:/requests?seg=inbox'), findsOne);
  });

  testWidgets('only the top two inbox items are listed', (t) async {
    await _pump(t,
        _overrides(user: _manager, inbox: [_inbox(1), _inbox(2), _inbox(3)]));
    expect(find.text('مستند 3'), findsNothing);
    expect(find.text('3'), findsOne);
  });

  testWidgets('a failing balance does not blank the home', (t) async {
    await _pump(t, _overrides(balanceError: Exception('boom')));
    expect(find.text('تعذّر تحميل رصيد الإجازات'), findsOne);
    expect(find.byType(HeroTodayCard), findsOne);
    expect(find.text('دوام هذا الشهر'), findsOne);
  });

  testWidgets('an attention row pushes its route', (t) async {
    await _pump(
        t,
        _overrides(attention: const [
          AttentionItem(
              kind: AttentionKind.rejectedRecord,
              title: 'رُفض تسجيل حضور',
              subtitle: 'سبب',
              route: '/attendance/history?date=2026-10-16'),
        ]));
    expect(find.text('يحتاج انتباهك'), findsOne);
    await t.tap(find.text('رُفض تسجيل حضور'));
    await t.pumpAndSettle();
    expect(find.text('route:/attendance/history?date=2026-10-16'), findsOne);
  });

  testWidgets('a stat tile navigates to its tab', (t) async {
    await _pump(t, _overrides());
    await t.tap(find.text('رصيد الإجازات'));
    await t.pumpAndSettle();
    expect(find.text('route:/requests'), findsOne);
  });

  testWidgets('the home can be pulled to refresh', (t) async {
    await _pump(t, _overrides());
    expect(find.byType(RefreshIndicator), findsOne);
  });
}
