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
  @override
  void initState() {
    super.initState();
    // Cold start (e.g. terminated-app notification tap): make sure both
    // lists are loaded so the lookup can resolve the request.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final found = ref.read(leaveRequestByIdProvider(widget.leaveRequestId));
      if (found == null) {
        ref.read(myLeaveRequestsProvider.notifier).refresh();
        ref.read(leaveApprovalsProvider.notifier).refresh();
      }
    });
  }

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
          backgroundColor:
              status == LeaveStatus.approved ? AppColors.approved : AppColors.rejected,
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
          content: Text(arabicMessageFor(failure.code, fallback: failure.message)),
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
    final request = ref.watch(leaveRequestByIdProvider(widget.leaveRequestId));
    final user = ref.watch(currentUserProvider);
    final isReviewing = ref.watch(leaveApprovalsProvider
        .select((s) => s.reviewingIds.contains(widget.leaveRequestId)));
    // Has either list finished an attempt? Used to decide loading vs not-found.
    final myLoaded = ref.watch(myLeaveRequestsProvider.select((s) => s.hasLoadedOnce));
    final approvalsLoaded =
        ref.watch(leaveApprovalsProvider.select((s) => s.hasLoadedOnce));

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
      body: _buildBody(request, myLoaded && approvalsLoaded),
      bottomNavigationBar: _buildActions(request, user?.id, isReviewing),
    );
  }

  Widget _buildBody(LeaveRequest? request, bool loadedBoth) {
    if (request == null) {
      if (!loadedBoth) {
        return const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded,
                  size: 56, color: AppColors.text3),
              const SizedBox(height: 14),
              Text('تعذّر العثور على طلب الإجازة.',
                  style: AppTheme.title(color: AppColors.text2)),
            ],
          ),
        ),
      );
    }

    final df = DateFormat('yyyy/MM/dd');
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
        if (request.leaveType != null && request.leaveType!.isNotEmpty)
          _InfoRow(
            icon: Icons.label_outline,
            label: 'نوع الإجازة',
            value: request.leaveType!,
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

  Widget? _buildActions(LeaveRequest? request, int? currentUserId, bool isReviewing) {
    if (request == null || !request.isPending) return null;
    // Only the assigned approving manager may act.
    final canReview =
        currentUserId != null && request.managerId == currentUserId;
    if (!canReview) return null;

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
          : Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmAndReview(LeaveStatus.rejected),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.rejected,
                      side: const BorderSide(color: AppColors.rejected, width: 1.5),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    label: const Text('رفض'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmAndReview(LeaveStatus.approved),
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
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});

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
