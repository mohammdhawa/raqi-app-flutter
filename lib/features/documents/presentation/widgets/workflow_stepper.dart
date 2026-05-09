import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/document.dart';

/// Vertical stepper used for sequential workflows.
///
/// Renders each approver as a numbered circle on the right (we're in RTL),
/// connected by a vertical line. Approved steps are filled green, rejected
/// red, pending mauve. Per the docs: "show the workflow as a vertical
/// stepper with order numbers".
class WorkflowStepper extends StatelessWidget {
  const WorkflowStepper({super.key, required this.steps});

  final List<WorkflowStep> steps;

  @override
  Widget build(BuildContext context) {
    final sorted = [...steps]..sort((a, b) => a.order.compareTo(b.order));
    return Column(
      children: [
        for (var i = 0; i < sorted.length; i++)
          _StepRow(
            step: sorted[i],
            isLast: i == sorted.length - 1,
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.isLast});

  final WorkflowStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (step.status) {
      WorkflowStepStatus.approved => (
        AppColors.statusApproved,
        Icons.check,
      ),
      WorkflowStepStatus.rejected => (
        AppColors.statusRejected,
        Icons.close,
      ),
      _ => (step.isChief ? AppColors.primary : AppColors.statusPending, null),
    };

    final circleSize = step.isChief ? 38.0 : 32.0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: circleSize,
                height: circleSize,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: icon != null
                    ? Icon(icon, color: AppColors.white, size: step.isChief ? 22 : 18)
                    : step.isChief
                        ? const Icon(Icons.shield_outlined, color: AppColors.white, size: 20)
                        : Text(
                            '${step.order}',
                            style: const TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: _StepBody(step: step),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepBody extends StatelessWidget {
  const _StepBody({required this.step});
  final WorkflowStep step;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: step.isChief
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: step.isChief ? AppColors.primary : AppColors.border,
          width: step.isChief ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        step.user.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (step.isChief) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'المسؤول الأعلى',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _statusLabel(step.status),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            step.user.email ?? '',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          if (step.signedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              DateFormat('yyyy/MM/dd · HH:mm').format(step.signedAt!),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (step.note != null && step.note!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                step.note!,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusLabel(WorkflowStepStatus status) {
    final (label, color) = switch (status) {
      WorkflowStepStatus.approved => ('اعتمد', AppColors.statusApproved),
      WorkflowStepStatus.rejected => ('رفض', AppColors.statusRejected),
      _ => ('بانتظار', AppColors.statusPending),
    };
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }
}
