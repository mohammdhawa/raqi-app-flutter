import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/theme/app_colors.dart';
import '../../domain/leave.dart';
import 'leave_status_chip.dart';

/// A single leave request row used by both the "my requests" and the
/// "approvals" lists. When [showRequester] is true the requester's name is
/// shown (approvals view); otherwise the approving manager is shown.
class LeaveRequestTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy/MM/dd');
    final counterpartLabel = showRequester
        ? (request.requesterName ?? 'مقدم الطلب')
        : (request.managerName ?? 'المعتمد');
    final counterpartIcon =
        showRequester ? Icons.person_outline_rounded : Icons.verified_user_outlined;

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
                  child: const Icon(
                    Icons.event_available_outlined,
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
                      Text(
                        _daysLabel(request.days) +
                            (request.leaveType != null &&
                                    request.leaveType!.isNotEmpty
                                ? ' · ${request.leaveType}'
                                : ''),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.text2,
                        ),
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
}
