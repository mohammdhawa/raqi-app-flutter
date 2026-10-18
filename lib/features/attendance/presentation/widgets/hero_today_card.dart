import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/format.dart';
import '../../../../shared/widgets/status_pill.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/attendance_record.dart';
import '../../domain/leave.dart';
import '../../domain/pending_attendance_record.dart' show AttendanceSyncStatus;
import '../../domain/today_attendance_item.dart';
import '../providers/attendance_controller.dart';
import '../providers/leave_providers.dart';

/// Where the employee's day stands, as the hero card sees it.
enum HeroPhase { disabled, notCheckedIn, checkedIn, done, onLeave }

/// Everything the hero card shows, derived from today's attendance.
class HeroTodayModel {
  const HeroTodayModel({
    required this.phase,
    this.checkedInAt,
    this.worked = Duration.zero,
    this.isPendingSync = false,
    this.leaveLabel,
  });

  final HeroPhase phase;

  /// When the open check-in happened. Only set while [phase] is checkedIn.
  final DateTime? checkedInAt;

  /// Time worked today; includes the still-open shift up to "now".
  final Duration worked;

  /// The latest valid record is still only on this device, not confirmed by
  /// the server. The card says so instead of claiming a confirmed state.
  final bool isPendingSync;

  /// Name of the approved leave. Only set while [phase] is onLeave.
  final String? leaveLabel;
}

/// Derives the hero state from today's records.
///
/// Rejected, missing-checkout and failed rows are not attendance the server
/// counts, so they are ignored for the same reason the action rule ignores
/// them (see `resolveLatestAttendance`).
HeroTodayModel buildHeroModel({
  required bool attendanceEnabled,
  required List<TodayAttendanceItem> today,
  required LeaveRequest? approvedLeaveToday,
  required String? leaveTypeLabel,
  required DateTime now,
}) {
  if (!attendanceEnabled) return const HeroTodayModel(phase: HeroPhase.disabled);

  final valid = today
      .where((i) =>
          !i.isRejected &&
          !i.isMissingCheckout &&
          i.status != AttendanceSyncStatus.failed)
      .toList()
    ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

  if (valid.isEmpty) {
    if (approvedLeaveToday != null) {
      return HeroTodayModel(
        phase: HeroPhase.onLeave,
        leaveLabel:
            leaveTypeLabel ?? approvedLeaveToday.leaveType ?? 'إجازة',
      );
    }
    return const HeroTodayModel(phase: HeroPhase.notCheckedIn);
  }

  // Clock skew between device and server must never print a negative
  // duration, so every span is clamped at zero.
  Duration span(DateTime from, DateTime to) {
    final d = to.difference(from);
    return d.isNegative ? Duration.zero : d;
  }

  var worked = Duration.zero;
  DateTime? openSince;
  for (final item in valid) {
    if (item.type == AttendanceType.checkIn) {
      openSince = item.recordedAt;
    } else if (openSince != null) {
      worked += span(openSince, item.recordedAt);
      openSince = null;
    }
  }

  final latest = valid.last;
  final isPending = latest.status != AttendanceSyncStatus.synced;
  if (latest.type == AttendanceType.checkIn) {
    return HeroTodayModel(
      phase: HeroPhase.checkedIn,
      checkedInAt: latest.recordedAt,
      worked: worked + span(latest.recordedAt, now),
      isPendingSync: isPending,
    );
  }
  return HeroTodayModel(
    phase: HeroPhase.done,
    worked: worked,
    isPendingSync: isPending,
  );
}

/// The hero model for the signed-in user. Widgets read this instead of
/// building the model themselves, so tests can override it directly.
final heroTodayModelProvider = Provider.autoDispose<HeroTodayModel>((ref) {
  // Watched so the model recomputes at midnight.
  ref.watch(currentLocalDayProvider);
  final leave = ref.watch(approvedLeaveTodayProvider).valueOrNull;
  return buildHeroModel(
    attendanceEnabled: ref.watch(currentUserProvider)?.attendanceCheck ?? false,
    today: ref.watch(todayAttendanceProvider),
    approvedLeaveToday: leave,
    leaveTypeLabel: ref.watch(leaveTypeByIdProvider(leave?.leaveTypeId))?.label,
    now: DateTime.now(),
  );
});

/// Whether a check-in/out capture is running. Split out of the controller
/// state so the card (and its tests) never touch the camera/DB/network
/// controller until the button is tapped.
final attendanceCapturingProvider = Provider.autoDispose<bool>((ref) {
  return ref.watch(attendanceControllerProvider.select((s) => s.isCapturing));
});

/// The navy "today" card: today's attendance state and the single gold
/// check-in/out button.
class HeroTodayCard extends ConsumerStatefulWidget {
  const HeroTodayCard({super.key, this.compact = false, this.onOpenDay});

  /// Hides the big value and puts the action beside the summary line.
  final bool compact;

  /// Opens the day's details; offered once the day is complete.
  final VoidCallback? onOpenDay;

  @override
  ConsumerState<HeroTodayCard> createState() => _HeroTodayCardState();
}

class _HeroTodayCardState extends ConsumerState<HeroTodayCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // The counter only needs a heartbeat while a shift is open.
    ref.listenManual<HeroPhase>(
      heroTodayModelProvider.select((m) => m.phase),
      (_, phase) => _syncTicker(phase == HeroPhase.checkedIn),
      fireImmediately: true,
    );
  }

  void _syncTicker(bool running) {
    if (!running) {
      _ticker?.cancel();
      _ticker = null;
    } else {
      // The model's `worked` is computed against DateTime.now() when the
      // provider runs, so a rebuild alone would show a stale value.
      _ticker ??= Timer.periodic(
        const Duration(minutes: 1),
        (_) => ref.invalidate(heroTodayModelProvider),
      );
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _handleTap(AttendanceType nextType) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(attendanceControllerProvider.notifier);
    final ok = await notifier.checkInOrOut(nextType);
    if (!mounted) return;

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
  Widget build(BuildContext context) {
    final model = ref.watch(heroTodayModelProvider);
    final action = ref.watch(attendanceActionProvider);
    final capturing = ref.watch(attendanceCapturingProvider);
    final compact = widget.compact;

    final (big, label) = _copy(model);
    final showAction = model.phase == HeroPhase.notCheckedIn ||
        model.phase == HeroPhase.checkedIn;
    final showDetails =
        model.phase == HeroPhase.done && widget.onOpenDay != null;
    final blocked = action.disabledReason != null;

    final goldButton = showAction
        ? _GoldButton(
            label: action.nextType == AttendanceType.checkIn
                ? 'تسجيل الحضور'
                : 'تسجيل الانصراف',
            capturing: capturing,
            onPressed: (capturing || blocked)
                ? null
                : () => _handleTap(action.nextType),
            fullWidth: !compact,
          )
        : null;
    final detailsButton = showDetails
        ? OutlinedButton(
            onPressed: widget.onOpenDay,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              minimumSize: Size(compact ? 0 : double.infinity, 48),
            ),
            child: Text('عرض تفاصيل اليوم', style: AppTheme.label()),
          )
        : null;
    final actionButton = goldButton ?? detailsButton;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppColors.r3xl),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            start: -18,
            top: -18,
            child: Opacity(
              opacity: 0.12,
              child: Image.asset(
                'assets/logo-symbol-gold.png',
                width: 120,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        arabicWeekdayDayMonth(DateTime.now()),
                        style: AppTheme.bodyS(color: AppColors.textOnDark2),
                      ),
                    ),
                    if (_pill(model) case final pill?) pill,
                  ],
                ),
                const SizedBox(height: 12),
                if (compact)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          [big, label].whereType<String>().join(' · '),
                          style: AppTheme.label(color: Colors.white),
                        ),
                      ),
                      if (actionButton != null) ...[
                        const SizedBox(width: 12),
                        actionButton,
                      ],
                    ],
                  )
                else ...[
                  if (big != null)
                    Text(
                      big,
                      style: AppTheme.display(color: Colors.white),
                    ),
                  if (label != null)
                    Text(
                      label,
                      style: AppTheme.bodyS(color: AppColors.textOnDark2),
                    ),
                  if (actionButton != null) ...[
                    const SizedBox(height: 16),
                    actionButton,
                  ],
                ],
                if (showAction && action.disabledReason != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    action.disabledReason!,
                    textAlign: TextAlign.center,
                    style: AppTheme.caption(color: AppColors.textOnDark2),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The big value and the caption under it for [model]'s phase.
  (String?, String?) _copy(HeroTodayModel model) => switch (model.phase) {
        HeroPhase.notCheckedIn => ('ابدأ يومك', 'سجّل حضورك عند الوصول'),
        HeroPhase.checkedIn => (
            isolateLtr(formatDuration(model.worked)),
            'ساعات العمل اليوم',
          ),
        HeroPhase.done => (
            isolateLtr(formatDuration(model.worked)),
            'إجمالي ساعات اليوم',
          ),
        HeroPhase.onLeave => (model.leaveLabel, 'لا يلزم تسجيل الحضور اليوم'),
        HeroPhase.disabled => ('تسجيل الحضور غير مفعّل لحسابك', null),
      };

  Widget? _pill(HeroTodayModel model) {
    switch (model.phase) {
      case HeroPhase.notCheckedIn:
        return StatusPill(
          label: 'لم تسجّل بعد',
          icon: Icons.schedule_rounded,
          fg: Colors.white,
          bg: Colors.white.withValues(alpha: 0.16),
        );
      case HeroPhase.checkedIn:
        return model.isPendingSync
            ? const StatusPill(
                label: 'حضور محفوظ على الجهاز',
                icon: Icons.cloud_upload_outlined,
                fg: AppColors.pendingText,
                bg: AppColors.pendingBg,
              )
            : StatusPill(
                label:
                    'حاضر · منذ ${isolateLtr(formatClock(model.checkedInAt!))}',
                icon: Icons.check_circle_outline_rounded,
                fg: AppColors.approvedText,
                bg: AppColors.approvedBg,
              );
      case HeroPhase.done:
        return model.isPendingSync
            ? const StatusPill(
                label: 'انصراف محفوظ على الجهاز',
                icon: Icons.cloud_upload_outlined,
                fg: AppColors.pendingText,
                bg: AppColors.pendingBg,
              )
            : const StatusPill(
                label: 'اكتمل الدوام',
                icon: Icons.task_alt_rounded,
                fg: AppColors.approvedText,
                bg: AppColors.approvedBg,
              );
      case HeroPhase.onLeave:
        return const StatusPill(
          label: 'إجازة',
          icon: Icons.beach_access_rounded,
          fg: AppColors.dayLeaveText,
          bg: AppColors.dayLeaveBg,
        );
      case HeroPhase.disabled:
        return null;
    }
  }
}

/// The card's single gold action. 52 px high; a spinner replaces the label
/// while a capture runs.
class _GoldButton extends StatelessWidget {
  const _GoldButton({
    required this.label,
    required this.capturing,
    required this.onPressed,
    required this.fullWidth,
  });

  final String label;
  final bool capturing;
  final VoidCallback? onPressed;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.primary,
        disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.45),
        disabledForegroundColor: AppColors.primary.withValues(alpha: 0.6),
        minimumSize: Size(fullWidth ? double.infinity : 0, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.rXl),
        ),
      ),
      child: capturing
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            )
          : Text(label, style: AppTheme.labelL(color: AppColors.primary)),
    );
  }
}
