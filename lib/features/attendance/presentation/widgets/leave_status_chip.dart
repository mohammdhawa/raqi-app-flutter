import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/leave.dart';

/// Small colored pill showing a leave request's status — mirrors the visual
/// language of the shared document [StatusChip].
class LeaveStatusChip extends StatelessWidget {
  const LeaveStatusChip({super.key, required this.status, this.large = false});

  final LeaveStatus status;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final (dotColor, textColor, bgColor) = switch (status) {
      LeaveStatus.pending => (
          AppColors.pending,
          AppColors.pendingText,
          AppColors.pendingBg,
        ),
      LeaveStatus.approved => (
          AppColors.approved,
          AppColors.approvedText,
          AppColors.approvedBg,
        ),
      LeaveStatus.rejected => (
          AppColors.rejected,
          AppColors.rejectedText,
          AppColors.rejectedBg,
        ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 10,
        vertical: large ? 5 : 4,
      ),
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
            status.arabicLabel,
            style: TextStyle(
              color: textColor,
              fontSize: large ? 12 : 11,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
