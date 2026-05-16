import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../features/documents/domain/document.dart';

/// Small colored pill showing status. Uses a colored dot + label layout.
/// Shared for document-level status and individual workflow-step status.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
    this.large = false,
    this.dense = false,
  });

  final DocumentStatus status;
  final bool large;
  /// Legacy compat — accepted but visuals now driven by [large].
  final bool dense;

  StatusChip.fromStep({
    super.key,
    required WorkflowStepStatus stepStatus,
    this.large = false,
    this.dense = false,
  }) : status = switch (stepStatus) {
         WorkflowStepStatus.approved => DocumentStatus.approved,
         WorkflowStepStatus.rejected => DocumentStatus.rejected,
         _ => DocumentStatus.pending,
       };

  @override
  Widget build(BuildContext context) {
    final (label, dotColor, textColor, bgColor) = switch (status) {
      DocumentStatus.pending => (
        'قيد الانتظار',
        AppColors.pending,
        AppColors.pendingText,
        AppColors.pendingBg,
      ),
      DocumentStatus.approved => (
        'معتمد',
        AppColors.approved,
        AppColors.approvedText,
        AppColors.approvedBg,
      ),
      DocumentStatus.rejected => (
        'مرفوض',
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
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
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