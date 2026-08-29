import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/theme/app_colors.dart';
import '../../domain/leave.dart';
import '../providers/leave_providers.dart';
import 'leave_status_chip.dart';

/// A single leave request row used by both the "my requests" and the
/// "approvals" lists. When [showRequester] is true the requester's name is
/// shown (approvals view); otherwise the approving manager is shown.
///
/// Nothing here switches on the raw `leave_type` string: it holds the Arabic
/// label on rows filed since types existed and raw free text (`annual`,
/// `sick`) on older ones, so it is safe to *display* and useless to reason
/// with. Icons, colours and the balance badge come from [LeaveRequest.leaveTypeId]
/// and [LeaveRequest.deductsBalance] instead.
class LeaveRequestTile extends ConsumerWidget {
  const LeaveRequestTile({
    super.key,
    required this.request,
    required this.onTap,
    this.showRequester = false,
  });

  final LeaveRequest request;
  final VoidCallback onTap;
  final bool showRequester;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat('yyyy/MM/dd');
    // An excuse has no approving manager — HR filed it already approved, on
    // the employee's behalf. Naming the (null) approver "المعتمد" made a row
    // the employee never submitted look like an ordinary request of theirs.
    final isExcuse = request.isExcuse;
    final counterpartLabel = showRequester
        ? (request.requesterName ?? 'مقدم الطلب')
        : isExcuse
            ? 'عذر مسجّل من الموارد البشرية'
            : (request.managerName ?? 'المعتمد');
    final counterpartIcon = showRequester
        ? Icons.person_outline_rounded
        : isExcuse
            ? Icons.assignment_ind_outlined
            : Icons.verified_user_outlined;
    // The stored label, falling back to the cached vocabulary when the row
    // carries an id but no text.
    final typeLabel = (request.leaveType?.isNotEmpty ?? false)
        ? request.leaveType
        : ref.watch(leaveTypeByIdProvider(request.leaveTypeId))?.label;
    final chainProgress = _chainProgressLabel(request);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppColors.r2xl),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppColors.r2xl),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isExcuse
                        ? Icons.assignment_turned_in_outlined
                        : Icons.event_available_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${df.format(request.startDate)} — ${df.format(request.endDate)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _daysLabel(request.days) +
                                  (typeLabel != null ? ' · $typeLabel' : ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.text2,
                              ),
                            ),
                          ),
                          if (!request.deductsBalance) ...[
                            const SizedBox(width: 6),
                            const _NonDeductingBadge(),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                LeaveStatusChip(status: request.status),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(counterpartIcon, size: 14, color: AppColors.text3),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    counterpartLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.text2,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_left_rounded,
                  size: 20,
                  color: AppColors.text3,
                ),
              ],
            ),
            if (chainProgress != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.account_tree_outlined,
                    size: 14,
                    color: AppColors.pendingText,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      chainProgress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.pendingText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _daysLabel(int days) {
    if (days == 1) return 'يوم واحد';
    if (days == 2) return 'يومان';
    if (days <= 10) return '$days أيام';
    return '$days يوماً';
  }

  /// Pending rows name the current approver and expose the chain position at a
  /// glance. Legacy single-approver rows have no chain and retain the compact
  /// one-line layout they had before this field existed.
  String? _chainProgressLabel(LeaveRequest request) {
    if (!request.isPending || request.approvals.isEmpty) return null;
    final currentId = request.currentApproverId ?? request.managerId;
    LeaveApprovalStep? current;
    for (final step in request.approvals) {
      if (step.userId == currentId) {
        current = step;
        break;
      }
    }
    if (current == null) return null;
    final progress =
        '${request.stepNumberOf(current)} / ${request.approvals.length}';
    return current.hasName
        ? 'بانتظار: ${current.userName} · $progress'
        : 'سلسلة الموافقة: $progress';
  }
}

/// Marks a row whose days were NOT charged to the annual balance. Driven by
/// the snapshot the request carries, so a type whose policy changed later
/// still reads the way it was actually charged.
class _NonDeductingBadge extends StatelessWidget {
  const _NonDeductingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.approvedBg,
        borderRadius: BorderRadius.circular(AppColors.pill),
      ),
      child: const Text(
        'لا تُخصم',
        style: TextStyle(
          fontSize: 10,
          height: 1.4,
          fontWeight: FontWeight.w700,
          color: AppColors.approvedText,
        ),
      ),
    );
  }
}
