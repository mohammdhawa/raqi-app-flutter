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
/// notification taps (`leave_request_id`). The server's `can_review` decides
/// whether actions are live in a sequential chain; old/cached rows fall back
/// to the legacy current-manager equality.
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
      final updated = await ref
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
          content: Text(_reviewOutcomeMessage(status, updated)),
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
          content: Text(
            arabicLeaveReviewMessage(failure.message) ??
                arabicMessageFor(failure.code, fallback: failure.message),
          ),
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
      body: _buildBody(requestAsync, user?.id),
      bottomNavigationBar: _buildActions(request, user?.id, isReviewing),
    );
  }

  Widget _buildBody(
    AsyncValue<LeaveRequest?> requestAsync,
    int? currentUserId,
  ) {
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
    final currentApproverName = _currentApproverName(request);
    final viewerCanReview = request.canBeReviewedBy(currentUserId);
    // The action bar already names the current approver to a viewer who is
    // waiting for their turn. Showing the same sentence twice on one screen
    // reads as a rendering fault, so the banner steps aside for it and covers
    // the viewers the bar does not: the requester, and an approver who has
    // already acted.
    final waitingBarWillShow =
        !viewerCanReview && (request.stepFor(currentUserId)?.isPending ?? false);

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
          value:
              request.deductsBalance ? 'تُخصم من الرصيد' : 'لا تُخصم من الرصيد',
        ),
        if (typeLabel != null)
          _InfoRow(
            icon: Icons.label_outline,
            label: 'نوع الإجازة',
            value: typeLabel,
          ),
        if (currentApproverName != null)
          _InfoRow(
            icon: Icons.verified_user_outlined,
            label: request.isPending ? 'المعتمد الحالي' : 'صاحب القرار النهائي',
            value: currentApproverName,
          ),
        if (request.requesterName != null)
          _InfoRow(
            icon: Icons.person_outline_rounded,
            label: 'مقدم الطلب',
            value: request.requesterName!,
          ),
        if (request.isPending &&
            !viewerCanReview &&
            !waitingBarWillShow &&
            currentApproverName != null) ...[
          const SizedBox(height: 8),
          _WaitingForApproverBanner(name: currentApproverName),
        ],
        if (request.approvals.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('سلسلة الموافقة', style: AppTheme.heading3()),
          const SizedBox(height: 12),
          _LeaveApprovalChain(request: request),
        ],
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
    if (!request.canBeReviewedBy(currentUserId)) {
      // Every approver can see a pending chain before their turn. Keep the
      // controls visible but disabled so the screen explains that the action
      // exists and what must happen before it becomes available.
      //
      // Only while their own step is still PENDING, though. The approvals
      // queue returns a request to EVERY approver on it, so an approver who
      // has already approved — or whose step was skipped by someone else's
      // rejection, or reassigned away — keeps reaching this screen with the
      // request still pending on somebody after them. Promising them the
      // actions "when the request reaches you" describes a hand-off that will
      // never happen: their step is closed. They get the chain and the waiting
      // banner in the body instead, as does an employee viewing their own
      // request, who holds no step at all.
      if (!(request.stepFor(currentUserId)?.isPending ?? false)) return null;
      return _WaitingActionBar(
        currentApproverName: _currentApproverName(request),
      );
    }

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
                        key: const Key('leave-reject-button'),
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

/// Confirms what actually happened, which an approval part-way down a chain
/// does not settle.
///
/// The server answers an intermediate approval with the request still
/// `pending` on the next approver, so telling this one their request "has been
/// approved" claims a decision the people after them have yet to make. The
/// review call hands back exactly that updated request; this reads it instead
/// of assuming the tapped button was the last word.
String _reviewOutcomeMessage(LeaveStatus status, LeaveRequest updated) {
  if (status != LeaveStatus.approved) return 'تم رفض طلب الإجازة.';
  if (!updated.isPending) return 'تم اعتماد طلب الإجازة.';
  // Named from `current_approver_id` alone — deliberately NOT through
  // [_currentApproverName], whose legacy `manager_id` fallback is exactly the
  // wrong thing to consult one instant after an approval: that field is
  // updated lazily, so a response that has not moved it on yet still names the
  // approver who just acted, and "waiting for approval from <you>" is worse
  // than naming nobody. Unnamed is always true; wrongly named is not.
  final next = _chainNameFor(updated, updated.currentApproverId);
  return next == null
      ? 'تم تسجيل موافقتك — الطلب بانتظار المعتمد التالي.'
      : 'تم تسجيل موافقتك — الطلب بانتظار موافقة $next.';
}

/// The chain's own name for [userId], or null when no step names them or the
/// step carried no usable name.
String? _chainNameFor(LeaveRequest request, int? userId) {
  if (userId == null) return null;
  for (final step in request.approvals) {
    if (step.userId == userId && step.hasName) return step.userName;
  }
  return null;
}

/// Resolves the display name from the chain first because that is the durable
/// workflow history. [LeaveRequest.managerName] is retained as the fallback
/// for legacy rows and partial list projections.
///
/// The id is resolved the way [_LeaveApprovalChain] and LeaveRequestTile
/// resolve it — `current_approver_id` when the payload carries one, else the
/// legacy `manager_id`, which on a pending row still names whoever must act
/// and afterwards names whoever decided. Reading only `current_approver_id`
/// left a list projection (which omits it, and omits the nested `manager` that
/// [LeaveRequest.managerName] is parsed from) with no name at all, while the
/// chain rendered directly above named the approver correctly.
String? _currentApproverName(LeaveRequest request) {
  final fromChain =
      _chainNameFor(request, request.currentApproverId ?? request.managerId);
  if (fromChain != null) return fromChain;
  final managerName = request.managerName;
  return managerName == null || managerName.isEmpty ? null : managerName;
}

/// The same pending state is useful to the requester and to a later approver:
/// it names the person who must act now instead of leaving a generic pending
/// chip to imply that anybody in the chain can review.
class _WaitingForApproverBanner extends StatelessWidget {
  const _WaitingForApproverBanner({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.pendingBg,
        borderRadius: BorderRadius.circular(AppColors.rLg),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded,
              size: 18, color: AppColors.pendingText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'بانتظار موافقة $name',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.pendingText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ordered, request-specific workflow. A skipped step is intentionally gray
/// and uses a dash icon — never the pending gold/hourglass treatment — because
/// a rejection means no work will ever be requested from that approver.
class _LeaveApprovalChain extends StatelessWidget {
  const _LeaveApprovalChain({required this.request});

  final LeaveRequest request;

  @override
  Widget build(BuildContext context) {
    final ordered = request.orderedApprovals;
    // `current_approver_id` whenever the payload carries one; on a pending
    // legacy row `manager_id` still names whoever must act. After a final
    // decision that field names the decider instead, which is no longer a
    // current step, so it is deliberately not consulted then.
    final effectiveCurrentId = request.currentApproverId ??
        (request.isPending ? request.managerId : null);
    return Column(
      children: [
        for (var index = 0; index < ordered.length; index++)
          _LeaveApprovalStepRow(
            step: ordered[index],
            number: request.stepNumberOf(ordered[index]),
            isCurrent: ordered[index].userId == effectiveCurrentId &&
                ordered[index].status == LeaveApprovalStatus.pending,
            isLast: index == ordered.length - 1,
          ),
      ],
    );
  }
}

class _LeaveApprovalStepRow extends StatelessWidget {
  const _LeaveApprovalStepRow({
    required this.step,
    required this.number,
    required this.isCurrent,
    required this.isLast,
  });

  final LeaveApprovalStep step;

  /// The step's 1-based position, from [LeaveRequest.stepNumberOf] — not
  /// `step.approvalOrder`, which a projection that omitted the field leaves
  /// at 0.
  final int number;
  final bool isCurrent;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final (icon, foreground, background) = switch (step.status) {
      LeaveApprovalStatus.approved => (
          Icons.check_rounded,
          AppColors.approved,
          AppColors.approvedBg,
        ),
      LeaveApprovalStatus.rejected => (
          Icons.close_rounded,
          AppColors.rejected,
          AppColors.rejectedBg,
        ),
      LeaveApprovalStatus.skipped => (
          Icons.horizontal_rule_rounded,
          AppColors.text3,
          AppColors.surface2,
        ),
      LeaveApprovalStatus.pending when isCurrent => (
          Icons.hourglass_top_rounded,
          AppColors.pendingText,
          AppColors.pendingBg,
        ),
      LeaveApprovalStatus.pending => (
          Icons.schedule_rounded,
          AppColors.text3,
          AppColors.surface2,
        ),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: background,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isCurrent ? AppColors.pending : foreground,
                      width: isCurrent ? 2 : 1,
                    ),
                  ),
                  child: Icon(icon, size: 16, color: foreground),
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
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppColors.rLg),
                border: Border.all(
                  color: isCurrent ? AppColors.pending : AppColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.userName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: background,
                          borderRadius: BorderRadius.circular(AppColors.pill),
                        ),
                        child: Text(
                          step.status.arabicLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isCurrent ? 'الخطوة $number · الدور الحالي' : 'الخطوة $number',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          isCurrent ? AppColors.pendingText : AppColors.text3,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  if (step.reviewedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('yyyy/MM/dd · HH:mm').format(step.reviewedAt!),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A later approver has access to the request but cannot act early. Disabled
/// controls make that capability boundary explicit, while the message names
/// the current predecessor so the screen never looks broken.
class _WaitingActionBar extends StatelessWidget {
  const _WaitingActionBar({this.currentApproverName});

  final String? currentApproverName;

  @override
  Widget build(BuildContext context) {
    final name = currentApproverName;
    return Container(
      key: const Key('leave-waiting-action-bar'),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: AppColors.shActionBar,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name == null
                ? 'لم يحن دورك بعد. ستتاح الإجراءات عند وصول الطلب إليك.'
                : 'بانتظار موافقة $name. ستتاح الإجراءات عند وصول الطلب إليك.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.text2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('leave-reject-button-disabled'),
                  onPressed: null,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  label: const Text('رفض'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  key: const Key('leave-approve-button-disabled'),
                  onPressed: null,
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: const Text('اعتماد'),
                ),
              ),
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
                Text('عذر مسجّل من الموارد البشرية', style: AppTheme.label()),
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
