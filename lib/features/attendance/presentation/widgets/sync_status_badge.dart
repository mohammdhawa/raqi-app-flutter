import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/pending_attendance_record.dart';

/// Small colored pill showing a queued record's sync status — mirrors
/// [StatusChip]'s dot + label layout, with the palette the spec calls for:
/// green = synced, orange/gold = pending, red = failed.
class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({super.key, required this.status});

  final AttendanceSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, dotColor, textColor, bgColor) = switch (status) {
      AttendanceSyncStatus.synced => (
        'تمت المزامنة',
        AppColors.approved,
        AppColors.approvedText,
        AppColors.approvedBg,
      ),
      AttendanceSyncStatus.pending => (
        'بانتظار المزامنة',
        AppColors.pending,
        AppColors.pendingText,
        AppColors.pendingBg,
      ),
      AttendanceSyncStatus.failed => (
        'فشلت المزامنة',
        AppColors.rejected,
        AppColors.rejectedText,
        AppColors.rejectedBg,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppColors.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
