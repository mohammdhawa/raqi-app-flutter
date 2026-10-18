import 'package:doc_approval/features/attendance/data/attendance_local_db.dart';
import 'package:doc_approval/features/attendance/domain/attendance_record.dart';
import 'package:doc_approval/features/attendance/domain/month_days.dart';
import 'package:doc_approval/features/attendance/domain/pending_attendance_record.dart';
import 'package:doc_approval/features/attendance/presentation/providers/attendance_queue_controller.dart';
import 'package:doc_approval/features/attendance/presentation/widgets/month_calendar.dart';
import 'package:doc_approval/shared/widgets/day_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

class _UnusedDb extends Fake implements AttendanceLocalDb {}

/// Records which ids were dismissed instead of touching SQLite.
class _FakeQueue extends AttendanceQueueController {
  _FakeQueue() : super(_UnusedDb(), null);

  final dismissed = <int>[];

  @override
  Future<void> dismiss(int id) async => dismissed.add(id);
}

final _day = DateTime(2026, 10, 16);

PendingAttendanceRecord _failed(int id) => PendingAttendanceRecord(
      id: id,
      type: AttendanceType.checkIn,
      latitude: 0,
      longitude: 0,
      selfiePath: 'x.jpg',
      recordedAt: DateTime(2026, 10, 16, 8, 5),
      status: AttendanceSyncStatus.failed,
      errorMessage: 'خارج نطاق موقع العمل',
    );

Future<_FakeQueue> _open(WidgetTester t, DayEntry entry) async {
  final queue = _FakeQueue();
  await pumpTestApp(
    t,
    Builder(
      builder: (context) => TextButton(
        onPressed: () => showDaySheet(context, entry),
        child: const Text('open'),
      ),
    ),
    overrides: [attendanceQueueProvider.overrideWith((ref) => queue)],
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return queue;
}

void main() {
  testWidgets('a failed capture is labelled rejected with its reason',
      (t) async {
    await _open(
      t,
      DayEntry(day: _day, state: DayState.rejected, pending: [_failed(42)]),
    );
    // One pill in the sheet header, one on the row — never «بانتظار المزامنة».
    expect(find.text('مرفوض'), findsNWidgets(2));
    expect(find.text('بانتظار المزامنة'), findsNothing);
    expect(find.text('خارج نطاق موقع العمل'), findsOne);
  });

  testWidgets('«حذف» on a failed row dismisses it and closes the sheet',
      (t) async {
    final queue = await _open(
      t,
      DayEntry(day: _day, state: DayState.rejected, pending: [_failed(42)]),
    );
    final button = find.widgetWithText(TextButton, 'حذف');
    expect(t.getSize(button).height, greaterThanOrEqualTo(48));
    await t.tap(button);
    await t.pumpAndSettle();
    expect(queue.dismissed, [42]);
    expect(find.text('خارج نطاق موقع العمل'), findsNothing);
  });

  testWidgets('a still-pending row offers no dismiss', (t) async {
    await _open(
      t,
      DayEntry(
        day: _day,
        state: DayState.pendingSync,
        pending: [
          PendingAttendanceRecord(
            id: 3,
            type: AttendanceType.checkIn,
            latitude: 0,
            longitude: 0,
            selfiePath: 'x.jpg',
            recordedAt: DateTime(2026, 10, 16, 8),
          ),
        ],
      ),
    );
    expect(find.text('بانتظار المزامنة'), findsNWidgets(2));
    expect(find.widgetWithText(TextButton, 'حذف'), findsNothing);
  });
}
