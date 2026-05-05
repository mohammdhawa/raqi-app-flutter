import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../features/documents/domain/document.dart';

/// Small colored pill showing status. Used both for document-level status
/// and individual workflow-step status (they share the same enum values).
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
    this.dense = false,
  });

  final DocumentStatus status;
  final bool dense;

  StatusChip.fromStep({
    super.key,
    required WorkflowStepStatus stepStatus,
    this.dense = false,
  }) : status = switch (stepStatus) {
         WorkflowStepStatus.approved => DocumentStatus.approved,
         WorkflowStepStatus.rejected => DocumentStatus.rejected,
         _ => DocumentStatus.pending,
       };

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (status) {
      DocumentStatus.pending => (
        'قيد الانتظار',
        AppColors.statusPending,
        AppColors.statusPendingBg,
      ),
      DocumentStatus.approved => (
        'معتمد',
        AppColors.statusApproved,
        AppColors.statusApprovedBg,
      ),
      DocumentStatus.rejected => (
        'مرفوض',
        AppColors.statusRejected,
        AppColors.statusRejectedBg,
      ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 12,
        vertical: dense ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: dense ? 11 : 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
