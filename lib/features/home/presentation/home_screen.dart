import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/personal_data_refresh.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/format.dart';
import '../../../shared/widgets/card_kit.dart';
import '../../attendance/domain/leave.dart';
import '../../attendance/domain/month_days.dart';
import '../../attendance/presentation/providers/attendance_controller.dart';
import '../../attendance/presentation/providers/attendance_queue_controller.dart';
import '../../attendance/presentation/providers/leave_providers.dart';
import '../../attendance/presentation/providers/month_attendance_providers.dart';
import '../../attendance/presentation/widgets/hero_today_card.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/providers/auth_controller.dart';
import '../../notifications/presentation/widgets/notification_bell_icon.dart';
import '../../requests/domain/request_item.dart';
import '../../requests/presentation/providers/requests_providers.dart';
import '../domain/attention_items.dart';

/// الرئيسية: who I am, today, my numbers, what needs me, and (for approvers
/// and managers) what waits on me. Every card loads on its own, so one failing
/// endpoint never blanks the screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final today = ref.watch(currentLocalDayProvider);
    final month = DateTime(today.year, today.month);
    final balance = ref.watch(leaveBalanceProvider);
    final days = ref.watch(monthDaysProvider(month));
    final attention = ref.watch(attentionItemsProvider);
    final canReview = ref.watch(canReviewRequestsProvider);

    final balanceTile = CardSlot<LeaveBalance>(
      value: balance,
      subject: 'رصيد الإجازات',
      onRetry: () => ref.invalidate(leaveBalanceProvider),
      builder: (b) => StatTile(
        label: 'رصيد الإجازات',
        value: '${b.remainingDays}',
        unit: 'يوماً',
        caption: 'إجازة سنوية',
        icon: Icons.beach_access_outlined,
        onTap: () => context.go('/requests'),
      ),
    );
    final monthTile = CardSlot<List<DayEntry>>(
      value: days,
      subject: 'دوام هذا الشهر',
      onRetry: () => ref.invalidate(monthRecordsProvider(month)),
      builder: (list) {
        final s = summarizeMonth(list);
        return StatTile(
          label: 'دوام هذا الشهر',
          value: '${s.presentDays}',
          unit: 'يوماً',
          caption: '${isolateLtr(formatDuration(s.worked))} ساعة عمل',
          icon: Icons.event_available_outlined,
          onTap: () => context.go('/attendance'),
        );
      },
    );
    // A retry row needs the full width; two of them side by side would not fit.
    final anyFailed = (balance.hasError && !balance.hasValue) ||
        (days.hasError && !days.hasValue);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _Header(user: user),
              const SizedBox(height: 16),
              HeroTodayCard(onOpenDay: () => context.go('/attendance')),
              const SizedBox(height: 14),
              if (anyFailed) ...[
                balanceTile,
                const SizedBox(height: 12),
                monthTile,
              ] else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: balanceTile),
                      const SizedBox(width: 12),
                      Expanded(child: monthTile),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              const UnavailableCard(
                title: 'الرواتب',
                body: 'ستظهر هنا رواتبك وكشوفها عند تفعيل الخدمة.',
              ),
              if (attention.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('يحتاج انتباهك',
                    style: AppTheme.title(color: AppColors.text)),
                const SizedBox(height: 8),
                for (final item in attention) ...[
                  _AttentionTile(item: item),
                  const SizedBox(height: 8),
                ],
              ],
              if (canReview) ...[
                const SizedBox(height: 12),
                const _PendingDecisionsCard(),
              ],
              if (user != null && (user.isManager || user.isChief)) ...[
                const SizedBox(height: 14),
                const UnavailableCard(
                  title: 'فريقي اليوم',
                  body: 'حضور فريقك اليوم سيظهر هنا عند تفعيل الخدمة.',
                  icon: Icons.groups_outlined,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Today's attendance and queue, as دوامي reloads them, plus every other
  /// personal source the cards read.
  Future<void> _refresh(WidgetRef ref) => Future.wait([
        ref.read(attendanceQueueProvider.notifier).refresh(),
        ref.read(attendanceControllerProvider.notifier).reload(),
        refreshPersonalData(ref),
      ]);
}

class _Header extends StatelessWidget {
  const _Header({required this.user});

  final User? user;

  /// First letters of the first two words of the name.
  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.take(2).map((w) => String.fromCharCode(w.runes.first)).join();
  }

  @override
  Widget build(BuildContext context) {
    final name = user?.name ?? '';
    final initials = _initials(name);
    final unit = [user?.departmentName, user?.sectionName]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' · ');

    return Row(
      children: [
        ExcludeSemantics(
          child: CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primary,
            child: initials.isEmpty
                ? const Icon(Icons.person_outline, color: AppColors.textOnDark)
                : Text(initials,
                    style: AppTheme.label(color: AppColors.textOnDark)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('أهلاً', style: AppTheme.caption(color: AppColors.text2)),
              if (name.isNotEmpty)
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.title(color: AppColors.text)),
              if (unit.isNotEmpty)
                Text(unit,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption(color: AppColors.text2)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const NotificationBellIcon(onDarkBackground: false),
      ],
    );
  }
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({required this.item});

  final AttentionItem item;

  @override
  Widget build(BuildContext context) {
    final (icon, fg, bg) = switch (item.kind) {
      AttentionKind.failedCapture => (
          Icons.error_outline_rounded,
          AppColors.rejectedText,
          AppColors.rejectedBg
        ),
      AttentionKind.rejectedRecord => (
          Icons.block_rounded,
          AppColors.rejectedText,
          AppColors.rejectedBg
        ),
      AttentionKind.missingCheckout => (
          Icons.logout_rounded,
          AppColors.pendingText,
          AppColors.pendingBg
        ),
      AttentionKind.requestDecided => (
          Icons.fact_check_outlined,
          AppColors.primary,
          AppColors.surface2
        ),
    };
    return AttentionRow(
      icon: icon,
      fg: fg,
      bg: bg,
      title: item.title,
      subtitle: item.subtitle,
      onTap: () {
        // `/attendance` is a tab root; the rest are pushed over the shell.
        if (item.route == '/attendance') {
          context.go(item.route);
        } else {
          context.push(item.route);
        }
      },
    );
  }
}

class _PendingDecisionsCard extends ConsumerWidget {
  const _PendingDecisionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxFeedProvider);
    final count = ref.watch(pendingDecisionsCountProvider);

    return CardSlot<List<RequestItem>>(
      value: inbox,
      subject: 'القرارات المعلّقة',
      onRetry: () {
        ref.invalidate(documentsAwaitingMeProvider);
        ref.read(leaveApprovalsProvider.notifier).load();
      },
      builder: (items) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppColors.rXl),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.how_to_vote_outlined,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('بانتظار قراري',
                      style: AppTheme.label(color: AppColors.text)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.pendingBg,
                    borderRadius: BorderRadius.circular(AppColors.pill),
                  ),
                  child: Text('$count',
                      style: AppTheme.label(color: AppColors.pendingText)),
                ),
              ],
            ),
            for (final item in items.take(2))
              InkWell(
                onTap: () => context.push(item.route),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.bodyS(color: AppColors.text)),
                              Text(
                                item.requesterName ?? item.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.caption(color: AppColors.text2),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_left_rounded,
                            size: 22, color: AppColors.text2),
                      ],
                    ),
                  ),
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => context.go('/requests?seg=inbox'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text('عرض كل الطلبات'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
