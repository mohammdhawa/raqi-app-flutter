import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/errors/api_failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/leave.dart';
import '../providers/leave_providers.dart';
import '../widgets/leave_status_chip.dart';

/// Detail view for a single leave request. Opened from the lists and from
/// notification taps (`leave_request_id`). When the current user is the
/// assigned approving manager and the request is pending, approve / reject
/// actions are shown.
class LeaveRequestDetailScreen extends ConsumerStatefulWidget {
  const LeaveRequestDetailScreen({super.key, required this.leaveRequestId});

  final int leaveRequestId;

  @override
  ConsumerState<LeaveRequestDetailScreen> createState() =>
      _LeaveRequestDetailScreenState();
}

class _LeaveRequestDetailScreenState
    extends ConsumerState<LeaveRequestDetailScreen> {
  Future<void> _review(LeaveStatus status) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(leaveApprovalsProvider.notifier)
          .review(widget.leaveRequestId, status);
      // Keep the requester-facing list consistent too.
      ref.read(myLeaveRequestsProvider.notifier).refresh();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: status == LeaveStatus.approved
              ? AppColors.approved
              : AppColors.rejected,
          content: Text(
            status == LeaveStatus.approved
                ? 'تم اعتماد طلب الإجازة.'
                : 'تم رفض طلب الإجازة.',
          ),
        ),
      );
      // The reviewed request may drop out of the (filtered) approvals list,
      // so return to it rather than leaving a stale detail view behind.
      if (context.canPop()) context.pop();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.rejected,
          content:
              Text(arabicMessageFor(failure.code, fallback: failure.message)),
        ),
      );
    }
  }

  Future<void> _confirmAndReview(LeaveStatus status) async {
    final isApprove = status == LeaveStatus.approved;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isApprove ? 'اعتماد الطلب' : 'رفض الطلب'),
        content: Text(
          isApprove
              ? 'هل أنت متأكد من اعتماد طلب الإجازة؟'
              : 'هل أنت متأكد من رفض طلب الإجازة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isApprove ? 'اعتماد' : 'رفض',
              style: TextStyle(
                color: isApprove ? AppColors.approved : AppColors.rejected,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await _review(status);
  }

  @override
  Widget build(BuildContext context) {
    // Resolved independently of the lists' status filters — a notification
    // must open its request whatever the user last filtered by.
    final requestAsync =
        ref.watch(leaveRequestDetailProvider(widget.leaveRequestId));
    final request = requestAsync.valueOrNull;
    final user = ref.watch(currentUserProvider);
    final isReviewing = ref.watch(leaveApprovalsProvider
        .select((s) => s.reviewingIds.contains(widget.leaveRequestId)));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('تفاصيل طلب الإجازة'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.chevron_right),
        ),
      ),
      body: _buildBody(requestAsync),
      bottomNavigationBar: _buildActions(request, user?.id, isReviewing),
    );
  }

  Widget _buildBody(AsyncValue<LeaveRequest?> requestAsync) {
    final request = requestAsync.valueOrNull;

    if (request == null) {
      if (requestAsync.isLoading) {
        return const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        );
      }
      // A lookup that failed (offline) is not the same as one that found
      // nothing — offering a retry on the first and not the second is the
      // difference between "try again" and "stop trying".
      final failure = requestAsync.error;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                failure == null
                    ? Icons.search_off_rounded
                    : Icons.wifi_off_rounded,
                size: 56,
                color: AppColors.text3,
              ),
              const SizedBox(height: 14),
              Text(
                failure is ApiFailure
                    ? arabicMessageFor(failure.code, fallback: failure.message)
                    : failure != null
                        ? 'تعذّر تحميل طلب الإجازة.'
                        : 'تعذّر العثور على طلب الإجازة.',
                textAlign: TextAlign.center,
                style: AppTheme.title(color: AppColors.text2),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(
                    leaveRequestDetailProvider(widget.leaveRequestId)),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final df = DateFormat('yyyy/MM/dd');
    // The stored label, falling back to the cached vocabulary when the row
    // carries an id but no text. Never parsed for meaning — see LeaveRequestTile.
    final typeLabel = (request.leaveType?.isNotEmpty ?? false)
        ? request.leaveType
        : ref.watch(leaveTypeByIdProvider(request.leaveTypeId))?.label;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Row(
          children: [
            Text('الحالة', style: AppTheme.heading3()),
            const Spacer(),
            LeaveStatusChip(status: request.status, large: true),
          ],
        ),
        // An approved leave the employee never submitted needs an explanation
        // on the screen they land on from the notification, not just a status
        // chip that reads like any other approval.
        if (request.isExcuse) ...[
          const SizedBox(height: 14),
          const _ExcuseBanner(),
        ],
        const SizedBox(height: 16),
        _InfoRow(
          icon: Icons.login_rounded,
          label: 'من تاريخ',
          value: df.format(request.startDate),
        ),
        _InfoRow(
          icon: Icons.logout_rounded,
          label: 'إلى تاريخ',
          value: df.format(request.endDate),
        ),
        _InfoRow(
          icon: Icons.timelapse_rounded,
          label: 'أيام العمل المحسوبة',
          value: '${request.days} ${request.days == 1 ? "يوم" : "أيام"}',
        ),
        _InfoRow(
          icon: request.deductsBalance
              ? Icons.remove_circle_outline
              : Icons.verified_outlined,
          label: 'أثر الرصيد',
          value: request.deductsBalance
              ? 'تُخصم من الرصيد'
              : 'لا تُخصم من الرصيد',
        ),
        if (typeLabel != null)
          _InfoRow(
            icon: Icons.label_outline,
            label: 'نوع الإجازة',
            value: typeLabel,
          ),
        if (request.managerName != null)
          _InfoRow(
            icon: Icons.verified_user_outlined,
            label: 'المدير المعتمد',
            value: request.managerName!,
          ),
        if (request.requesterName != null)
          _InfoRow(
            icon: Icons.person_outline_rounded,
            label: 'مقدم الطلب',
            value: request.requesterName!,
          ),
        if (request.reason != null && request.reason!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('السبب', style: AppTheme.label(color: AppColors.text2)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppColors.rLg),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(request.reason!, style: AppTheme.body()),
          ),
        ],
      ],
    );
  }

  Widget? _buildActions(
      LeaveRequest? request, int? currentUserId, bool isReviewing) {
    if (request == null || !request.isPending) return null;
    // Only the assigned approving manager may act.
    final canReview =
        currentUserId != null && request.managerId == currentUserId;
    if (!canReview) return null;

    // A legacy row that names its own author as approver. Submission-side
    // enforcement only covers rows created after it shipped, so requests
    // stored before it still exist and still reach this screen — and the
    // review gate is a bare `manager_id == caller` equality that they pass.
    //
    // The backend refuses to APPROVE them (ReviewLeaveRequest's status rule)
    // but deliberately leaves REJECT open, so the person holding the row can
    // still close it out rather than being stranded behind a gate nobody can
    // pass. The UI mirrors exactly that: reject stays, approve goes.
    final isSelfAssigned =
        request.requesterId != null && request.requesterId == request.managerId;

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        boxShadow: AppColors.shActionBar,
      ),
      child: isReviewing
          ? const SizedBox(
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppColors.primary),
                ),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isSelfAssigned) ...[
                  Container(
                    key: const Key('leave-self-approval-notice'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.rejectedBg,
                      borderRadius: BorderRadius.circular(AppColors.rLg),
                      border: Border.all(
                        color: AppColors.rejected.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: AppColors.rejected),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'لا يمكن اعتماد طلب إجازة مقدَّمه هو نفسه معتمِده. '
                            'يمكن رفض الطلب فقط.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.rejected,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _confirmAndReview(LeaveStatus.rejected),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.rejected,
                          side: const BorderSide(
                              color: AppColors.rejected, width: 1.5),
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        label: const Text('رفض'),
                      ),
                    ),
                    // Approve is dropped entirely rather than disabled: a
                    // greyed-out button invites tapping it to find out why,
                    // and the notice above already gives the reason.
                    if (!isSelfAssigned) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          key: const Key('leave-approve-button'),
                          onPressed: () =>
                              _confirmAndReview(LeaveStatus.approved),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.approved,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          icon: const Icon(Icons.check_rounded, size: 20),
                          label: const Text('اعتماد'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }
}

/// Explains an approved leave the employee never asked for: HR recorded it to
/// justify a day they were marked absent. There is no review step on one of
/// these, so the approve/reject bar never appears either.
class _ExcuseBanner extends StatelessWidget {
  const _ExcuseBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accentTint,
        borderRadius: BorderRadius.circular(AppColors.rLg),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.assignment_ind_outlined,
              size: 20, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('عذر مسجّل من الموارد البشرية',
                    style: AppTheme.label()),
                const SizedBox(height: 4),
                Text(
                  'سُجّل هذا العذر نيابةً عنك لتبرير غياب، ولم يُقدَّم كطلب '
                  'إجازة، لذلك لا يحتاج إلى موافقة.',
                  style: AppTheme.bodyS(color: AppColors.text2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.text3),
          const SizedBox(width: 10),
          Text(
            label,
            style: AppTheme.bodyS(color: AppColors.text2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTheme.label(),
            ),
          ),
        ],
      ),
    );
  }
}
