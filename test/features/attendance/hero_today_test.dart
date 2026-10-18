import 'package:doc_approval/features/attendance/domain/attendance_action.dart';
import 'package:doc_approval/features/attendance/domain/attendance_record.dart';
import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:doc_approval/features/attendance/domain/pending_attendance_record.dart';
import 'package:doc_approval/features/attendance/domain/today_attendance_item.dart';
import 'package:doc_approval/features/attendance/presentation/providers/attendance_controller.dart';
import 'package:doc_approval/features/attendance/presentation/widgets/hero_today_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

final now = DateTime(2026, 10, 18, 13, 43);

TodayAttendanceItem inAt(int h, int m, {bool pending = false}) => pending
    ? TodayAttendanceItem.local(PendingAttendanceRecord(
        type: AttendanceType.checkIn,
        latitude: 0,
        longitude: 0,
        selfiePath: 'x.jpg',
        recordedAt: DateTime(2026, 10, 18, h, m)))
    : TodayAttendanceItem.remote(AttendanceRecord(
        id: 1,
        userId: 7,
        type: AttendanceType.checkIn,
        latitude: 0,
        longitude: 0,
        recordedAt: DateTime(2026, 10, 18, h, m),
        createdAt: DateTime(2026, 10, 18, h, m)));

TodayAttendanceItem outAt(int h, int m, {bool pending = false}) => pending
    ? TodayAttendanceItem.local(PendingAttendanceRecord(
        type: AttendanceType.checkOut,
        latitude: 0,
        longitude: 0,
        selfiePath: 'x.jpg',
        recordedAt: DateTime(2026, 10, 18, h, m)))
    : TodayAttendanceItem.remote(AttendanceRecord(
        id: 2,
        userId: 7,
        type: AttendanceType.checkOut,
        latitude: 0,
        longitude: 0,
        recordedAt: DateTime(2026, 10, 18, h, m),
        createdAt: DateTime(2026, 10, 18, h, m)));

HeroTodayModel build(
  List<TodayAttendanceItem> today, {
  bool enabled = true,
  LeaveRequest? leave,
  String? leaveLabel,
}) =>
    buildHeroModel(
      attendanceEnabled: enabled,
      today: today,
      approvedLeaveToday: leave,
      leaveTypeLabel: leaveLabel,
      now: now,
    );

LeaveRequest leaveRequest({String? leaveType}) => LeaveRequest(
      id: 1,
      startDate: DateTime(2026, 10, 18),
      endDate: DateTime(2026, 10, 18),
      status: LeaveStatus.approved,
      leaveType: leaveType,
    );

void main() {
  group('buildHeroModel', () {
    test('no records → notCheckedIn', () {
      expect(build(const []).phase, HeroPhase.notCheckedIn);
    });

    test('open check-in counts worked time to now', () {
      final m = build([inAt(8, 2)]);
      expect(m.phase, HeroPhase.checkedIn);
      expect(m.checkedInAt, DateTime(2026, 10, 18, 8, 2));
      expect(m.worked, const Duration(hours: 5, minutes: 41));
      expect(m.isPendingSync, isFalse);
    });

    test('pending check-in is not confirmed', () {
      final m = build([inAt(8, 2, pending: true)]);
      expect(m.isPendingSync, isTrue);
    });

    test('check-out closes the day and sums the pair', () {
      final m = build([outAt(16, 2), inAt(8, 2)]);
      expect(m.phase, HeroPhase.done);
      expect(m.worked, const Duration(hours: 8));
    });

    test('pending check-out marks the day pending', () {
      final m = build([inAt(8, 2), outAt(16, 2, pending: true)]);
      expect(m.phase, HeroPhase.done);
      expect(m.isPendingSync, isTrue);
    });

    test('rejected and missing-checkout rows are ignored', () {
      final rejected = TodayAttendanceItem.remote(AttendanceRecord(
        id: 3,
        userId: 7,
        type: AttendanceType.checkIn,
        latitude: 0,
        longitude: 0,
        recordedAt: DateTime(2026, 10, 18, 8),
        createdAt: DateTime(2026, 10, 18, 8),
        isRejected: true,
      ));
      final missing = TodayAttendanceItem.remote(AttendanceRecord(
        id: 4,
        userId: 7,
        type: AttendanceType.checkIn,
        latitude: 0,
        longitude: 0,
        recordedAt: DateTime(2026, 10, 18, 8),
        createdAt: DateTime(2026, 10, 18, 8),
        status: 'missing_checkout',
      ));
      expect(rejected.isRejected, isTrue);
      expect(missing.isMissingCheckout, isTrue);
      expect(build([rejected, missing]).phase, HeroPhase.notCheckedIn);
    });

    test('failed local rows are ignored', () {
      final failed = TodayAttendanceItem.local(PendingAttendanceRecord(
        type: AttendanceType.checkIn,
        latitude: 0,
        longitude: 0,
        selfiePath: 'x.jpg',
        recordedAt: DateTime(2026, 10, 18, 8),
        status: AttendanceSyncStatus.failed,
      ));
      expect(build([failed]).phase, HeroPhase.notCheckedIn);
    });

    test('attendanceCheck false → disabled even with records', () {
      expect(build([inAt(8, 2)], enabled: false).phase, HeroPhase.disabled);
    });

    test('approved leave with no records → onLeave with fallback labels', () {
      expect(
        build(const [], leave: leaveRequest(), leaveLabel: 'سنوية').leaveLabel,
        'سنوية',
      );
      expect(
        build(const [], leave: leaveRequest(leaveType: 'مرضية')).leaveLabel,
        'مرضية',
      );
      final m = build(const [], leave: leaveRequest());
      expect(m.phase, HeroPhase.onLeave);
      expect(m.leaveLabel, 'إجازة');
    });

    test('records outrank approved leave', () {
      expect(build([inAt(8, 2)], leave: leaveRequest()).phase,
          HeroPhase.checkedIn);
    });

    test('rolls over at midnight', () {
      // The controller only feeds today's items; with an empty list after
      // midnight the phase is notCheckedIn.
      expect(
        buildHeroModel(
          attendanceEnabled: true,
          today: const [],
          approvedLeaveToday: null,
          leaveTypeLabel: null,
          now: DateTime(2026, 10, 19, 0, 1),
        ).phase,
        HeroPhase.notCheckedIn,
      );
    });
  });

  group('HeroTodayCard', () {
    List<Override> overrides(
      HeroTodayModel model, {
      AttendanceAction? action,
      bool capturing = false,
    }) =>
        [
          heroTodayModelProvider.overrideWithValue(model),
          attendanceActionProvider.overrideWithValue(action ??
              const AttendanceAction(nextType: AttendanceType.checkIn)),
          attendanceCapturingProvider.overrideWithValue(capturing),
        ];

    testWidgets('disabledReason renders and disables the button', (t) async {
      await pumpTestApp(
        t,
        const Scaffold(body: HeroTodayCard()),
        overrides: overrides(
          build([inAt(8, 2)]),
          action: const AttendanceAction(
            nextType: AttendanceType.checkOut,
            disabledReason: 'انتظر',
          ),
        ),
      );
      expect(find.text('انتظر'), findsOneWidget);
      final button = t.widget<ElevatedButton>(find.ancestor(
        of: find.text('تسجيل الانصراف'),
        matching: find.byType(ElevatedButton),
      ));
      expect(button.onPressed, isNull);
      // Stop the live counter's timer before the test ends.
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('checkedIn shows pill, duration and enabled checkout',
        (t) async {
      await pumpTestApp(
        t,
        const Scaffold(body: HeroTodayCard()),
        overrides: overrides(
          build([inAt(8, 2)]),
          action: const AttendanceAction(nextType: AttendanceType.checkOut),
        ),
      );
      expect(find.textContaining('حاضر · منذ'), findsOneWidget);
      expect(find.textContaining('5:41'), findsOneWidget);
      expect(find.text('ساعات العمل اليوم'), findsOneWidget);
      final button = t.widget<ElevatedButton>(find.ancestor(
        of: find.text('تسجيل الانصراف'),
        matching: find.byType(ElevatedButton),
      ));
      expect(button.onPressed, isNotNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('pending check-in says it is saved on the device', (t) async {
      await pumpTestApp(
        t,
        const Scaffold(body: HeroTodayCard()),
        overrides: overrides(
          build([inAt(8, 2, pending: true)]),
          action: const AttendanceAction(nextType: AttendanceType.checkOut),
        ),
      );
      expect(find.text('حضور محفوظ على الجهاز'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('notCheckedIn invites the first check-in', (t) async {
      await pumpTestApp(
        t,
        const Scaffold(body: HeroTodayCard()),
        overrides: overrides(build(const [])),
      );
      expect(find.text('لم تسجّل بعد'), findsOneWidget);
      expect(find.text('ابدأ يومك'), findsOneWidget);
      expect(find.text('سجّل حضورك عند الوصول'), findsOneWidget);
      expect(find.text('تسجيل الحضور'), findsOneWidget);
    });

    testWidgets('done offers the day details', (t) async {
      var opened = 0;
      await pumpTestApp(
        t,
        Scaffold(body: HeroTodayCard(onOpenDay: () => opened++)),
        overrides: overrides(build([inAt(8, 2), outAt(16, 2)])),
      );
      expect(find.text('اكتمل الدوام'), findsOneWidget);
      expect(find.text('إجمالي ساعات اليوم'), findsOneWidget);
      expect(find.text('تسجيل الحضور'), findsNothing);
      await t.tap(find.text('عرض تفاصيل اليوم'));
      expect(opened, 1);
    });

    testWidgets('onLeave shows the leave label and no action', (t) async {
      await pumpTestApp(
        t,
        const Scaffold(body: HeroTodayCard()),
        overrides: overrides(
          build(const [], leave: leaveRequest(), leaveLabel: 'سنوية'),
        ),
      );
      expect(find.text('سنوية'), findsOneWidget);
      expect(find.text('لا يلزم تسجيل الحضور اليوم'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('disabled phase explains and offers no action', (t) async {
      await pumpTestApp(
        t,
        const Scaffold(body: HeroTodayCard()),
        overrides: overrides(build(const [], enabled: false)),
      );
      expect(find.text('تسجيل الحضور غير مفعّل لحسابك'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('capturing shows a spinner and disables the button',
        (t) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: overrides(build(const []), capturing: true),
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: HeroTodayCard()),
            ),
          ),
        ),
      );
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final button = t.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('compact hides the big value but keeps the action', (t) async {
      await pumpTestApp(
        t,
        const Scaffold(body: HeroTodayCard(compact: true)),
        overrides: overrides(build(const [])),
      );
      expect(find.text('ابدأ يومك'), findsNothing);
      expect(find.text('تسجيل الحضور'), findsOneWidget);
    });
  });
}
