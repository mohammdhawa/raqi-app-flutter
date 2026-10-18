import 'package:doc_approval/features/attendance/domain/attendance_action.dart';
import 'package:doc_approval/features/attendance/domain/attendance_record.dart';
import 'package:doc_approval/features/attendance/domain/month_days.dart';
import 'package:doc_approval/features/attendance/presentation/providers/attendance_controller.dart';
import 'package:doc_approval/features/attendance/presentation/providers/attendance_queue_controller.dart';
import 'package:doc_approval/features/attendance/presentation/providers/month_attendance_providers.dart';
import 'package:doc_approval/features/attendance/presentation/screens/attendance_tab_screen.dart';
import 'package:doc_approval/features/attendance/presentation/widgets/hero_today_card.dart';
import 'package:doc_approval/shared/widgets/day_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

final _month = DateTime(2026, 10);
final _today = DateTime(2026, 10, 18);

AttendanceRecord _rec(int id, AttendanceType type, int day, int h, int m,
        {bool rejected = false, String? reason}) =>
    AttendanceRecord(
      id: id,
      userId: 7,
      type: type,
      latitude: 0,
      longitude: 0,
      recordedAt: DateTime(2026, 10, day, h, m),
      createdAt: DateTime(2026, 10, day, h, m),
      isRejected: rejected,
      rejectionReason: reason,
    );

List<DayEntry> _fixture() {
  final present = [
    _rec(1, AttendanceType.checkIn, 7, 8, 2),
    _rec(2, AttendanceType.checkOut, 7, 16, 30),
  ];
  final rejected = [_rec(3, AttendanceType.checkIn, 5, 8, 0, rejected: true, reason: 'location')];
  return List.generate(31, (i) {
    final day = DateTime(2026, 10, i + 1);
    if (day.day == 7) {
      return DayEntry(
        day: day,
        state: DayState.present,
        records: present,
        worked: const Duration(hours: 8, minutes: 28),
      );
    }
    if (day.day == 5) {
      return DayEntry(day: day, state: DayState.rejected, records: rejected);
    }
    return DayEntry(
      day: day,
      state: day.isAfter(_today) ? DayState.future : DayState.noRecord,
    );
  });
}

Future<void> _pump(WidgetTester t, {int pending = 0}) async {
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await pumpTestApp(t, const AttendanceTabScreen(), overrides: [
    monthDaysProvider(_month).overrideWithValue(AsyncData(_fixture())),
    currentLocalDayProvider.overrideWithValue(_today),
    pendingAttendanceCountProvider.overrideWithValue(pending),
    heroTodayModelProvider.overrideWithValue(
        const HeroTodayModel(phase: HeroPhase.notCheckedIn)),
    attendanceActionProvider.overrideWithValue(
        const AttendanceAction(nextType: AttendanceType.checkIn)),
    attendanceCapturingProvider.overrideWithValue(false),
  ]);
}

void main() {
  testWidgets('calendar labels every past day with its state', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t);
    expect(find.bySemanticsLabel('الأربعاء 7 تشرين الأول — حاضر'), findsOne);
    expect(find.bySemanticsLabel('الإثنين 5 تشرين الأول — مرفوض'), findsOne);
    handle.dispose();
  });

  testWidgets('tapping a day opens its sheet', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t);
    await t.tap(find.bySemanticsLabel('الأربعاء 7 تشرين الأول — حاضر'));
    await t.pumpAndSettle();
    expect(find.text('مؤكد'), findsNWidgets(2));
    expect(find.text('ساعات العمل'), findsWidgets);
    expect(find.text('عرض في السجل'), findsNothing);
    handle.dispose();
  });

  testWidgets('a rejected day links to the history for that date', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t);
    await t.tap(find.bySemanticsLabel('الإثنين 5 تشرين الأول — مرفوض'));
    await t.pumpAndSettle();
    expect(find.text('الموقع المسجَّل لا يطابق موقع العمل'), findsOneWidget);
    await t.tap(find.text('عرض في السجل'));
    await t.pumpAndSettle();
    expect(find.text('route:/attendance/history?date=2026-10-05'),
        findsOneWidget);
    handle.dispose();
  });

  testWidgets('next month is disabled on the current month', (t) async {
    await _pump(t);
    final next = t.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left_rounded));
    expect(next.tooltip, 'الشهر التالي');
    expect(next.onPressed, isNull);
  });

  testWidgets('pending banner shows the count', (t) async {
    await _pump(t, pending: 1);
    expect(find.textContaining('سجل واحد بانتظار المزامنة'), findsOneWidget);
  });

  testWidgets('day cells are at least 48 px tall', (t) async {
    await _pump(t);
    final ink = find.ancestor(of: find.text('7'), matching: find.byType(InkWell));
    expect(ink, findsOneWidget);
    expect(t.getSize(ink).height, greaterThanOrEqualTo(48));
  });

  testWidgets('a screen reader can open a day through the tap action',
      (t) async {
    final handle = t.ensureSemantics();
    await _pump(t);
    t.semantics.tap(
        find.semantics.byLabel('الأربعاء 7 تشرين الأول — حاضر'));
    await t.pumpAndSettle();
    expect(find.text('مؤكد'), findsNWidgets(2));
    handle.dispose();
  });
}
