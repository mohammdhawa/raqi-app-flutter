import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/utils/format.dart';
import '../../attendance/domain/leave.dart';
import '../../auth/domain/user.dart';
import '../../documents/domain/document.dart';

enum RequestKind { leave, document }

enum RequestStatus {
  pending,
  approved,
  rejected,
  cancelled;

  String get label => switch (this) {
        RequestStatus.pending => 'قيد الانتظار',
        RequestStatus.approved => 'مقبول',
        RequestStatus.rejected => 'مرفوض',
        RequestStatus.cancelled => 'ملغى',
      };

  Color get fg => switch (this) {
        RequestStatus.pending => AppColors.pendingText,
        RequestStatus.approved => AppColors.approvedText,
        RequestStatus.rejected => AppColors.rejectedText,
        RequestStatus.cancelled => AppColors.text2,
      };

  Color get bg => switch (this) {
        RequestStatus.pending => AppColors.pendingBg,
        RequestStatus.approved => AppColors.approvedBg,
        RequestStatus.rejected => AppColors.rejectedBg,
        RequestStatus.cancelled => AppColors.surface2,
      };
}

/// One row of the الطلبات tab, whichever backend it came from. Leave requests
/// and approval-workflow documents are different models; the list only needs
/// what a row shows, so both are flattened into this.
class RequestItem {
  const RequestItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.sortDate,
    required this.route,
    this.stepLabel,
    this.requesterName,
  });

  final RequestKind kind;
  final int id;
  final String title;
  final String subtitle;
  final RequestStatus status;
  final String? stepLabel;
  final DateTime sortDate;
  final String route;
  final String? requesterName;
}

RequestItem requestFromLeave(LeaveRequest r, {String? typeLabel}) {
  final range = _sameDay(r.startDate, r.endDate)
      ? arabicDayMonth(r.startDate)
      : '${arabicDayMonth(r.startDate)} – ${arabicDayMonth(r.endDate)}';
  return RequestItem(
    kind: RequestKind.leave,
    id: r.id,
    title: typeLabel ?? r.leaveType ?? 'طلب إجازة',
    subtitle: '$range · ${arabicDays(r.days)}',
    status: switch (r.status) {
      LeaveStatus.pending => RequestStatus.pending,
      LeaveStatus.approved => RequestStatus.approved,
      LeaveStatus.rejected => RequestStatus.rejected,
      LeaveStatus.cancelled => RequestStatus.cancelled,
    },
    stepLabel: _leaveStepLabel(r),
    sortDate: r.createdAt ?? r.startDate,
    route: '/attendance/leave/requests/${r.id}',
    requesterName: r.requesterName,
  );
}

String? _leaveStepLabel(LeaveRequest r) {
  if (r.isExcuse) return 'سجّلتها الموارد البشرية';
  if (r.status == LeaveStatus.pending) {
    final chain = r.orderedApprovals;
    final current = chain.where((s) => s.isPending).firstOrNull;
    if (current != null && current.hasName) {
      return 'الخطوة ${r.stepNumberOf(current)} من ${chain.length}'
          ' · بانتظار ${current.userName}';
    }
    if (chain.isEmpty && (r.managerName?.isNotEmpty ?? false)) {
      return 'بانتظار ${r.managerName}';
    }
    return null;
  }
  if (r.status == LeaveStatus.approved) return 'اكتمل المسار';
  return null;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

RequestItem requestFromDocument(Document d) {
  final waiting = d.status == DocumentStatus.pending
      ? nextPendingApprovers(d)
      : const <User>[];
  return RequestItem(
    kind: RequestKind.document,
    id: d.id,
    title: d.title,
    subtitle: '${d.documentNumber ?? d.templateName ?? 'مستند'}'
        ' · ${arabicDayMonth(d.createdAt)}',
    status: switch (d.status) {
      DocumentStatus.pending => RequestStatus.pending,
      DocumentStatus.approved => RequestStatus.approved,
      DocumentStatus.rejected => RequestStatus.rejected,
    },
    stepLabel: waiting.isEmpty
        ? null
        : 'بانتظار ${waiting.map((u) => u.name).join('، ')}',
    sortDate: d.createdAt,
    route: '/documents/${d.id}',
    requesterName: d.creator.name,
  );
}

/// Who must act on [d] next.
///
/// `nextPendingUsers` is filled only by the details endpoint; the list endpoint
/// leaves it empty but eager-loads the workflow steps. So when it is empty this
/// mirrors the backend's `DocumentWorkflowService::getNextPendingUsers`:
/// pending managers first (lowest order only when sequential, all when
/// parallel), the first pending chief once no manager is left.
List<User> nextPendingApprovers(Document d) {
  if (d.status != DocumentStatus.pending) return const [];
  if (d.nextPendingUsers.isNotEmpty) return d.nextPendingUsers;

  final managers = d.workflows
      .where(
          (s) => s.role == 'manager' && s.status == WorkflowStepStatus.pending)
      .toList();
  if (managers.isNotEmpty) {
    if (d.workflowMode == WorkflowMode.parallel) {
      return [for (final s in managers) s.user];
    }
    final first = managers.map((s) => s.order).reduce((a, b) => a < b ? a : b);
    return [
      for (final s in managers)
        if (s.order == first) s.user,
    ];
  }

  final chief = d.workflows
      .where((s) => s.role == 'chief' && s.status == WorkflowStepStatus.pending)
      .firstOrNull;
  return chief == null ? const [] : [chief.user];
}

bool isAwaitingUser(Document d, int userId) =>
    nextPendingApprovers(d).any((u) => u.id == userId);

/// Newest first. While more documents are still unloaded, leave items older
/// than the oldest loaded document are dropped: the list must not claim an
/// order it has not loaded the rows to prove.
List<RequestItem> mergeRequests(
  List<RequestItem> leaves,
  List<RequestItem> documents, {
  required bool documentsHaveMore,
}) {
  var kept = leaves;
  if (documentsHaveMore && documents.isNotEmpty) {
    final oldest = documents
        .map((d) => d.sortDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    kept = [
      for (final l in leaves)
        if (!l.sortDate.isBefore(oldest)) l,
    ];
  }
  return [...kept, ...documents]
    ..sort((a, b) => b.sortDate.compareTo(a.sortDate));
}
