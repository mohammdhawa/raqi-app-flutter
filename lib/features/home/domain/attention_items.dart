import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/format.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/domain/attendance_record.dart';
import '../../attendance/domain/leave.dart';
import '../../attendance/domain/month_days.dart';
import '../../attendance/domain/pending_attendance_record.dart';
import '../../attendance/presentation/providers/attendance_controller.dart';
import '../../attendance/presentation/providers/attendance_queue_controller.dart';
import '../../attendance/presentation/providers/leave_providers.dart';
import '../../requests/domain/request_item.dart';

enum AttentionKind { failedCapture, rejectedRecord, missingCheckout, requestDecided }

/// One row of «يحتاج انتباهك»: something the employee should look at.
class AttentionItem {
  const AttentionItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final AttentionKind kind;
  final String title;
  final String subtitle;
  final String route;
}

/// How long a leave decision stays worth surfacing.
const _decisionWindow = Duration(days: 3);

const _maxItems = 3;

String _dateParam(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// What needs the employee's attention, at most [_maxItems], in
/// [AttentionKind] order and newest first within a kind.
List<AttentionItem> buildAttentionItems({
  required List<AttendanceRecord> recentRecords,
  required List<PendingAttendanceRecord> failedLocal,
  required List<LeaveRequest> myLeaves,
  required DateTime now,
}) {
  final failed = failedLocal.where((p) => p.isFailed).toList()
    ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
  final rejected = recentRecords.where((r) => r.isRejected).toList()
    ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
  final missing = recentRecords
      .where((r) => !r.isRejected && r.isMissingCheckout)
      .toList()
    ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
  final cutoff = now.subtract(_decisionWindow);
  final decided = myLeaves
      .where((l) =>
          (l.status == LeaveStatus.approved ||
              l.status == LeaveStatus.rejected) &&
          l.reviewedAt != null &&
          !l.reviewedAt!.isBefore(cutoff))
      .toList()
    ..sort((a, b) => b.reviewedAt!.compareTo(a.reviewedAt!));

  final items = <AttentionItem>[
    for (final p in failed)
      AttentionItem(
        kind: AttentionKind.failedCapture,
        title: 'لم يُقبل تسجيل ${p.type.arabicLabel}',
        subtitle: p.errorMessage ?? '',
        route: '/attendance',
      ),
    for (final r in rejected)
      AttentionItem(
        kind: AttentionKind.rejectedRecord,
        title: 'رُفض تسجيل ${r.type.arabicLabel}'
            ' يوم ${arabicWeekdayDayMonth(r.recordedAt)}',
        subtitle: r.rejectionReasonLabel,
        route: '/attendance/history?date=${_dateParam(r.recordedAt)}',
      ),
    for (final r in missing)
      AttentionItem(
        kind: AttentionKind.missingCheckout,
        title: 'لم يُسجَّل انصراف يوم ${arabicWeekdayDayMonth(r.recordedAt)}',
        subtitle: 'راجع اليوم في دوامي',
        route: '/attendance',
      ),
    for (final l in decided)
      () {
        final item = requestFromLeave(l);
        return AttentionItem(
          kind: AttentionKind.requestDecided,
          title: l.status == LeaveStatus.approved
              ? 'قُبل طلب ${item.title}'
              : 'رُفض طلب ${item.title}',
          subtitle: item.subtitle,
          route: item.route,
        );
      }(),
  ];
  return items.take(_maxItems).toList();
}

/// Attendance rows of the last 7 days, for rejected / missing-checkout items.
final recentRecordsProvider =
    FutureProvider.autoDispose<List<AttendanceRecord>>((ref) {
  final today = ref.watch(currentLocalDayProvider);
  return fetchAllMyRecords(
    ref.watch(attendanceRepositoryProvider),
    from: today.subtract(const Duration(days: 7)),
    to: today,
  );
});

/// The home screen's attention list. Watched instead of the leave notifier and
/// the queue so the screen rebuilds only when the list itself changes.
final attentionItemsProvider = Provider.autoDispose<List<AttentionItem>>((ref) {
  return buildAttentionItems(
    recentRecords: ref.watch(recentRecordsProvider).valueOrNull ?? const [],
    failedLocal: [
      for (final p in ref.watch(attendanceQueueProvider))
        if (p.isFailed) p,
    ],
    myLeaves: ref.watch(myLeaveRequestsProvider).requests,
    now: DateTime.now(),
  );
});
