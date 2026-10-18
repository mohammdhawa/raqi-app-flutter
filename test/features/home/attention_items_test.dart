import 'package:doc_approval/features/attendance/domain/attendance_record.dart';
import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:doc_approval/features/attendance/domain/pending_attendance_record.dart';
import 'package:doc_approval/features/home/domain/attention_items.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 18, 9);

AttendanceRecord _rec(int id, int day,
        {bool rejected = false, String? status}) =>
    AttendanceRecord(
      id: id,
      userId: 7,
      type: AttendanceType.checkIn,
      latitude: 0,
      longitude: 0,
      recordedAt: DateTime(2026, 10, day, 8),
      createdAt: DateTime(2026, 10, day, 8),
      isRejected: rejected,
      rejectionReason: rejected ? 'location' : null,
      status: status,
    );

AttendanceRecord missingCheckoutOn(int day) =>
    _rec(day, day, status: 'missing_checkout');
AttendanceRecord rejectedOn(int day) => _rec(100 + day, day, rejected: true);

PendingAttendanceRecord failedCheckIn() => PendingAttendanceRecord(
      type: AttendanceType.checkIn,
      latitude: 0,
      longitude: 0,
      selfiePath: 'x.jpg',
      recordedAt: DateTime(2026, 10, 18, 8),
      status: AttendanceSyncStatus.failed,
      errorMessage: 'خارج نطاق العمل',
    );

LeaveRequest _decided(DateTime reviewedAt,
        {LeaveStatus status = LeaveStatus.approved}) =>
    LeaveRequest(
      id: 5,
      startDate: DateTime(2026, 10, 25),
      endDate: DateTime(2026, 10, 26),
      status: status,
      leaveType: 'إجازة سنوية',
      reviewedAt: reviewedAt,
    );

LeaveRequest approvedYesterday() => _decided(DateTime(2026, 10, 17, 10));

List<AttentionItem> _build({
  List<AttendanceRecord> records = const [],
  List<PendingAttendanceRecord> failed = const [],
  List<LeaveRequest> leaves = const [],
}) =>
    buildAttentionItems(
        recentRecords: records,
        failedLocal: failed,
        myLeaves: leaves,
        now: _now);

void main() {
  test('attention items are capped at 3 in priority order', () {
    final items = buildAttentionItems(
      recentRecords: [missingCheckoutOn(17), rejectedOn(16)],
      failedLocal: [failedCheckIn()],
      myLeaves: [approvedYesterday()],
      now: _now,
    );
    expect(items.map((i) => i.kind), [
      AttentionKind.failedCapture,
      AttentionKind.rejectedRecord,
      AttentionKind.missingCheckout,
    ]);
  });

  test('decisions older than 3 days are not attention', () {
    expect(_build(leaves: [_decided(DateTime(2026, 10, 14))]), isEmpty);
  });

  test('a decision within 3 days is attention, worded by outcome', () {
    final approved = _build(leaves: [approvedYesterday()]).single;
    expect(approved.kind, AttentionKind.requestDecided);
    expect(approved.title, 'قُبل طلب إجازة سنوية');
    expect(approved.route, '/attendance/leave/requests/5');
    final rejected = _build(leaves: [
      _decided(DateTime(2026, 10, 17), status: LeaveStatus.rejected)
    ]).single;
    expect(rejected.title, 'رُفض طلب إجازة سنوية');
  });

  test('a pending leave is never a decision', () {
    expect(
        _build(leaves: [
          _decided(DateTime(2026, 10, 17), status: LeaveStatus.pending)
        ]),
        isEmpty);
  });

  test('rejected record routes to its history day', () {
    final item = _build(records: [rejectedOn(16)]).single;
    expect(item.route, '/attendance/history?date=2026-10-16');
    expect(item.title, 'رُفض تسجيل حضور يوم الجمعة 16 تشرين الأول');
    expect(item.subtitle, 'الموقع المسجَّل لا يطابق موقع العمل');
  });

  test('a rejected check-in is not also a missing checkout', () {
    final r = _rec(1, 16, rejected: true, status: 'missing_checkout');
    expect(_build(records: [r]).map((i) => i.kind),
        [AttentionKind.rejectedRecord]);
  });

  test('missing checkout points to the attendance tab', () {
    final item = _build(records: [missingCheckoutOn(17)]).single;
    expect(item.route, '/attendance');
    expect(item.title, 'لم يُسجَّل انصراف يوم السبت 17 تشرين الأول');
    expect(item.subtitle, 'راجع اليوم في دوامي');
  });

  test('failed capture shows the server message, only failed rows count', () {
    final item = _build(failed: [failedCheckIn()]).single;
    expect(item.title, 'لم يُقبل تسجيل حضور');
    expect(item.subtitle, 'خارج نطاق العمل');
    expect(item.route, '/attendance');
    final pending = PendingAttendanceRecord(
        type: AttendanceType.checkIn,
        latitude: 0,
        longitude: 0,
        selfiePath: 'x',
        recordedAt: _now);
    expect(_build(failed: [pending]), isEmpty);
  });

  test('newest first within a kind', () {
    final items =
        _build(records: [missingCheckoutOn(15), missingCheckoutOn(17)]);
    expect(items.first.title, contains('17'));
  });
}
