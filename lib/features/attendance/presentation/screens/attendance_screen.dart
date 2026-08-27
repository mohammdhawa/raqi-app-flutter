import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/domain/user.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../../notifications/presentation/widgets/notification_bell_icon.dart';
import '../../domain/attendance_record.dart';
import '../../domain/attendance_window.dart';
import '../../domain/pending_attendance_record.dart' show AttendanceSyncStatus;
import '../../domain/today_attendance_item.dart';
import '../providers/attendance_controller.dart';
import '../providers/attendance_queue_controller.dart';
import '../providers/leave_providers.dart';
import '../widgets/leave_balance_card.dart';
import '../widgets/sync_status_badge.dart';

/// Check-in/out home: status card, the big context-aware action button,
/// a pending-sync banner, and today's locally-captured records.
///
/// Doubles as the employee home screen (`/`, no back button — gated by
/// `User.isEmployee`/`attendanceCheck` in app_router.dart) and as a pushed
/// screen (`/attendance`) for other roles that have attendance enabled.
class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  Future<void> _confirmAndLogout(BuildContext context, WidgetRef ref) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'خروج',
              style: TextStyle(color: AppColors.rejected),
            ),
          ),
        ],
      ),
    );
    if (shouldLogout == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  Future<void> _handleTap(
    BuildContext context,
    WidgetRef ref,
    AttendanceType nextType,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(attendanceControllerProvider.notifier);
    final ok = await notifier.checkInOrOut(nextType);
    if (!context.mounted) return;

    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.approved,
          content: Text(
            nextType == AttendanceType.checkIn
                ? 'تم تسجيل الحضور — جارٍ المزامنة في الخلفية.'
                : 'تم تسجيل الانصراف — جارٍ المزامنة في الخلفية.',
          ),
        ),
      );
    } else {
      final error = ref.read(attendanceControllerProvider).captureError;
      if (error != null) {
        messenger.showSnackBar(
          SnackBar(backgroundColor: AppColors.rejected, content: Text(error)),
        );
        notifier.clearCaptureError();
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A queued record the server rejects is surfaced inline on its own row in
    // "today's records" below (a red, dismissible tile carrying the server's
    // Arabic message). We deliberately don't also raise a global SnackBar for
    // it: the app has a single app-level ScaffoldMessenger, so such a SnackBar
    // lingers across navigation and reappears on unrelated screens (documents,
    // etc.). The inline tile keeps the rejection where it belongs.
    final user = ref.watch(currentUserProvider);
    final status = ref.watch(attendanceStatusProvider);
    final controllerState = ref.watch(attendanceControllerProvider);
    final todayRecords = ref.watch(todayAttendanceProvider);
    final pendingCount = ref.watch(pendingAttendanceCountProvider);
    final topPadding = MediaQuery.of(context).padding.top;
    final isHome = !context.canPop();
    final nextType = status?.opposite ?? AttendanceType.checkIn;

    // Pre-disable the tapped action whenever we can already predict the server
    // will reject it — cutting down on failed round-trips. The server still has
    // the final say either way.
    String? disabledReason;
    if (nextType == AttendanceType.checkIn) {
      // Blocked once the day is complete or on approved leave. A checkout for
      // today (missing-checkout records are excluded upstream) means the
      // single daily shift is already done — no second check-in.
      // checkInBlockedReason stays in the chain even though the calendar no
      // longer blocks anything: it is the one hook a future day-off rule
      // would come back through.
      if (status == AttendanceType.checkOut) {
        disabledReason = 'لقد أكملت دوام اليوم — تم تسجيل الحضور والانصراف.';
      } else {
        disabledReason = checkInBlockedReason(DateTime.now());
        if (disabledReason == null &&
            ref.watch(approvedLeaveTodayProvider).valueOrNull != null) {
          disabledReason = 'لديك إجازة معتمدة اليوم — لا حاجة لتسجيل الحضور.';
        }
      }
    } else {
      // Checking out: block until the backend's minimum check-in→checkout gap
      // has elapsed, showing a live countdown while it hasn't.
      disabledReason = ref.watch(checkOutBlockedReasonProvider);
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Column(
          children: [
            _AttendanceHeader(
              topPadding: topPadding,
              user: user,
              isHome: isHome,
              onLogout: () => _confirmAndLogout(context, ref),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                // Both halves of the status: the local queue AND today's
                // server records. Refreshing only the queue left a refusal
                // filed by HR invisible — the one change the employee cannot
                // cause themselves, and the one that decides which button
                // they get.
                onRefresh: () async {
                  await Future.wait([
                    ref.read(attendanceQueueProvider.notifier).refresh(),
                    ref.read(attendanceControllerProvider.notifier).reload(),
                  ]);
                  ref.invalidate(approvedLeaveTodayProvider);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  children: [
                    _StatusCard(
                      status: status,
                      isLoading: controllerState.isBootstrapping,
                    ),
                    const SizedBox(height: 18),
                    _CheckInOutButton(
                      nextType: nextType,
                      isCapturing: controllerState.isCapturing,
                      disabledReason: disabledReason,
                      onTap: () => _handleTap(context, ref, nextType),
                    ),
                    if (pendingCount > 0) ...[
                      const SizedBox(height: 14),
                      _PendingBanner(count: pendingCount),
                    ],

                    // ── Leave management ──
                    const SizedBox(height: 18),
                    const _ApprovedLeaveBanner(),
                    LeaveBalanceCard(
                      onTap: () => context.push('/attendance/leave'),
                    ),
                    if (user?.isManager == true) ...[
                      const SizedBox(height: 12),
                      _LeaveActions(
                        onRequest: () =>
                            context.push('/attendance/leave/new'),
                        onApprovals: () => context
                            .push('/attendance/leave', extra: {'tab': 1}),
                      ),
                    ],

                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Text('سجلات اليوم', style: AppTheme.heading3()),
                        const Spacer(),
                        // Open to everyone: `/attendance/my-records` is
                        // auth-only and returns just the caller's own rows.
                        // Gating this on canViewAttendance left the employees
                        // who get refusal notifications — exactly the people
                        // told to go look — with nowhere to look. The screen
                        // keeps its 403 empty state as the backstop.
                        TextButton(
                          onPressed: () => context.push('/attendance/history'),
                          child: const Text('السجل الكامل'),
                        ),
                      ],
                    ),
                    if (todayRecords.isEmpty)
                      const _TodayEmptyState()
                    else
                      ...todayRecords.map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: _TodayRecordTile(record: r),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  APP BAR
// ═══════════════════════════════════════════════════════════════════════

class _AttendanceHeader extends StatelessWidget {
  const _AttendanceHeader({
    required this.topPadding,
    required this.user,
    required this.isHome,
    required this.onLogout,
  });

  final double topPadding;
  final User? user;
  final bool isHome;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      child: Stack(
        children: [
          // Radial gold gradient highlight — bottom-right
          Positioned(
            bottom: 0,
            right: 0,
            width: 90,
            height: 90,
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.7,
                  colors: [Color(0x2EC8A36B), Colors.transparent],
                ),
              ),
            ),
          ),

          Padding(
            padding: EdgeInsets.fromLTRB(12, topPadding + 10, 12, 16),
            child: Row(
              children: [
                // Trailing (left in RTL): leading action — logout on the
                // employee home, back arrow when pushed for other roles.
                if (isHome)
                  _HeaderIconBtn(icon: Icons.logout, onTap: onLogout)
                else
                  _HeaderIconBtn(
                    icon: Icons.arrow_forward_ios_rounded,
                    onTap: () => context.pop(),
                  ),
                const SizedBox(width: 8),
                const NotificationBellIcon(),
                const SizedBox(width: 8),
                // Same reasoning as the «السجل الكامل» button below: own
                // records are readable by any authenticated user.
                _HeaderIconBtn(
                  icon: Icons.history_rounded,
                  onTap: () => context.push('/attendance/history'),
                ),

                const Spacer(),

                // Title (center)
                Column(
                  children: [
                    const Text(
                      'الحضور والانصراف',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (user != null)
                      Text(
                        '${user!.name} · ${user!.role}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textOnDark2,
                        ),
                      ),
                  ],
                ),

                const Spacer(),

                // Leading (right in RTL): logo → tap to open About
                GestureDetector(
                  onTap: () => context.push('/about'),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/logo-symbol-gold.png',
                        width: 26,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.assured_workload_outlined,
                          color: AppColors.accent,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  const _HeaderIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  STATUS CARD
// ═══════════════════════════════════════════════════════════════════════

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.isLoading});

  final AttendanceType? status;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final (label, subtitle, icon, color) = switch (status) {
      AttendanceType.checkIn => (
        'أنت الآن في العمل',
        'آخر تسجيل: حضور',
        Icons.work_outline_rounded,
        AppColors.approved,
      ),
      AttendanceType.checkOut => (
        'أنت الآن خارج العمل',
        'آخر تسجيل: انصراف',
        Icons.home_outlined,
        AppColors.text2,
      ),
      null => (
        'لم تُسجّل أي حضور بعد',
        'ابدأ يومك بتسجيل الحضور',
        Icons.schedule_outlined,
        AppColors.pending,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.r2xl),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.title()),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTheme.bodyS(color: AppColors.text2)),
              ],
            ),
          ),
          if (isLoading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  CHECK-IN / CHECK-OUT BUTTON
// ═══════════════════════════════════════════════════════════════════════

class _CheckInOutButton extends StatelessWidget {
  const _CheckInOutButton({
    required this.nextType,
    required this.isCapturing,
    required this.onTap,
    this.disabledReason,
  });

  final AttendanceType nextType;
  final bool isCapturing;
  final VoidCallback onTap;

  /// When non-null, the action is pre-blocked client-side: the button is
  /// disabled and this Arabic reason is shown in place of the hint.
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final isCheckIn = nextType == AttendanceType.checkIn;
    final label = isCheckIn ? 'تسجيل حضور' : 'تسجيل انصراف';
    final isBlocked = disabledReason != null;

    return Opacity(
      opacity: isBlocked ? 0.55 : 1,
      child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppColors.r3xl),
      child: InkWell(
        onTap: (isCapturing || isBlocked) ? null : onTap,
        borderRadius: BorderRadius.circular(AppColors.r3xl),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [AppColors.primary, AppColors.primaryGrad],
            ),
            borderRadius: BorderRadius.circular(AppColors.r3xl),
            boxShadow: AppColors.shGold,
          ),
          child: isCapturing
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.accent,
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
                      'جارٍ تحديد الموقع والتقاط الصورة…',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isCheckIn
                            ? Icons.fingerprint_rounded
                            : Icons.exit_to_app_rounded,
                        color: AppColors.accent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      label,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      disabledReason ??
                          'يلتقط موقعك وصورة شخصية ويسجلهما تلقائيًا',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  PENDING-SYNC BANNER
// ═══════════════════════════════════════════════════════════════════════

class _PendingBanner extends ConsumerWidget {
  const _PendingBanner({required this.count});
  final int count;

  /// Escape hatch for a queue the server never accepts: confirm, then drop
  /// every pending record. Guarded by a dialog because it's irreversible —
  /// these records can't reach the server anymore either way.
  Future<void> _confirmDiscard(BuildContext context, WidgetRef ref) async {
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف السجلات المعلّقة'),
          content: Text(
            'سيتم حذف $count سجلًا لم يتمكن التطبيق من مزامنتها مع الخادم. '
            'لا يمكن التراجع عن هذا الإجراء. هل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'حذف',
                style: TextStyle(color: AppColors.rejected),
              ),
            ),
          ],
        ),
      ),
    );
    if (shouldDiscard == true) {
      await ref.read(attendanceQueueProvider.notifier).discardPending();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.pendingBg,
        borderRadius: BorderRadius.circular(AppColors.rLg),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_upload_outlined,
            color: AppColors.pendingText,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 1
                  ? 'يوجد سجل واحد بانتظار المزامنة — سيُرفع تلقائيًا عند توفر الاتصال.'
                  : 'يوجد $count سجلات بانتظار المزامنة — ستُرفع تلقائيًا عند توفر الاتصال.',
              style: AppTheme.bodyS(color: AppColors.pendingText),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _confirmDiscard(context, ref),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'حذف',
                style: AppTheme.bodyS(color: AppColors.pendingText).copyWith(
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  TODAY'S RECORDS
// ═══════════════════════════════════════════════════════════════════════

class _TodayRecordTile extends ConsumerWidget {
  const _TodayRecordTile({required this.record});
  final TodayAttendanceItem record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCheckIn = record.type == AttendanceType.checkIn;
    final isFailed = record.status == AttendanceSyncStatus.failed;
    // A refused record outranks every other tint: it is the one state where the
    // employee has to act, and it must never wear the green of a record that
    // counts.
    final tint = record.isRejected
        ? AppColors.rejected
        : record.isMissingCheckout
            ? AppColors.pending
            : isCheckIn
                ? AppColors.approved
                : AppColors.text2;
    final workHours = record.workHours;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.rLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCheckIn ? Icons.login_rounded : Icons.logout_rounded,
                  color: tint,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.type.arabicLabel,
                      style: AppTheme.label().copyWith(
                        decoration: record.isRejected
                            ? TextDecoration.lineThrough
                            : null,
                        color: record.isRejected ? AppColors.text2 : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('HH:mm').format(record.recordedAt),
                      style: AppTheme.captionS(color: AppColors.text2),
                    ),
                    // Worked hours live on the checkout row — and a refused one
                    // contributed none, so they would be a lie here.
                    if (!isCheckIn && workHours != null && !record.isRejected) ...[
                      const SizedBox(height: 2),
                      Text(
                        'ساعات العمل: ${formatWorkHours(workHours)}',
                        style: AppTheme.captionS(color: AppColors.text2),
                      ),
                    ],
                  ],
                ),
              ),
              if (record.isRejected)
                const _RejectedChip()
              else if (record.isMissingCheckout)
                const _IncompleteDayChip()
              else
                SyncStatusBadge(status: record.status),
            ],
          ),

          // Why HR refused the record. Spelled out on the row itself: the push
          // notification is long gone by the time they open the app, and
          // without the reason they cannot know what to do differently.
          if (record.isRejected && record.rejectionMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.rejectedBg,
                borderRadius: BorderRadius.circular(AppColors.rMd),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.gpp_bad_outlined,
                    color: AppColors.rejected,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.rejectionMessage!,
                          style: AppTheme.captionS(color: AppColors.rejected),
                        ),
                        // The refusal frees the day's check-in slot again, and
                        // saying so is the whole point of showing this row: the
                        // employee was told to record the day again and needs
                        // to know they still can.
                        if (record.type == AttendanceType.checkIn) ...[
                          const SizedBox(height: 4),
                          Text(
                            'يمكنك إعادة تسجيل الحضور لهذا اليوم.',
                            style: AppTheme.captionS(color: AppColors.text2)
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // A server-rejected queued entry: show why, with a dismiss action.
          if (isFailed && record.errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.rejectedBg,
                borderRadius: BorderRadius.circular(AppColors.rMd),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.rejected,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      record.errorMessage!,
                      style: AppTheme.captionS(color: AppColors.rejectedText),
                    ),
                  ),
                  if (record.localId != null)
                    GestureDetector(
                      onTap: () => ref
                          .read(attendanceQueueProvider.notifier)
                          .dismiss(record.localId!),
                      child: const Padding(
                        padding: EdgeInsets.only(right: 4, left: 2),
                        child: Icon(
                          Icons.close_rounded,
                          color: AppColors.rejectedText,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Marks a check-in the employee never closed (server `missing_checkout`),
/// so the day reads as incomplete rather than a full day worked.
/// Badge on a record HR refused. Deliberately the same shape as the
/// incomplete-day chip — it replaces the sync badge, because "synced" is true
/// but beside the point once the server has thrown the record out.
class _RejectedChip extends StatelessWidget {
  const _RejectedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.rejectedBg,
        borderRadius: BorderRadius.circular(AppColors.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.gpp_bad_outlined,
            color: AppColors.rejected,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            'غير مقبول',
            style: AppTheme.captionS(color: AppColors.rejected).copyWith(
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _IncompleteDayChip extends StatelessWidget {
  const _IncompleteDayChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.pendingBg,
        borderRadius: BorderRadius.circular(AppColors.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.report_gmailerrorred_outlined,
            color: AppColors.pendingText,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            'بدون انصراف',
            style: AppTheme.captionS(color: AppColors.pendingText).copyWith(
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayEmptyState extends StatelessWidget {
  const _TodayEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.event_note_outlined,
              color: AppColors.text3,
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'لا توجد تسجيلات اليوم بعد',
            style: AppTheme.label(color: AppColors.text2),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  LEAVE — approved-leave-today banner & manager actions
// ═══════════════════════════════════════════════════════════════════════

/// Surfaces "إجازة معتمدة" when the user has an approved leave covering
/// today. Renders nothing otherwise (or while loading / on error).
class _ApprovedLeaveBanner extends ConsumerWidget {
  const _ApprovedLeaveBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leave = ref.watch(approvedLeaveTodayProvider).valueOrNull;
    if (leave == null) return const SizedBox.shrink();

    final df = DateFormat('yyyy/MM/dd');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.approvedBg,
          borderRadius: BorderRadius.circular(AppColors.r2xl),
          border: Border.all(color: AppColors.approved.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: AppColors.approved,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.beach_access_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('إجازة معتمدة', style: AppTheme.title()),
                  const SizedBox(height: 2),
                  Text(
                    'أنت في إجازة معتمدة اليوم '
                    '(${df.format(leave.startDate)} — ${df.format(leave.endDate)}).',
                    style: AppTheme.bodyS(color: AppColors.approvedText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Manager-only quick actions: submit a request and open the approvals tab.
class _LeaveActions extends StatelessWidget {
  const _LeaveActions({required this.onRequest, required this.onApprovals});

  final VoidCallback onRequest;
  final VoidCallback onApprovals;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onRequest,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('طلب إجازة'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onApprovals,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.5),
              minimumSize: const Size.fromHeight(46),
            ),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('طلبات للموافقة'),
          ),
        ),
      ],
    );
  }
}
