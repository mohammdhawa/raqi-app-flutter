import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/format.dart';
import '../../../../shared/widgets/card_kit.dart';
import '../../../../shared/widgets/day_state.dart';
import '../../../../shared/widgets/status_pill.dart';
import '../../domain/month_days.dart';
import '../providers/attendance_controller.dart';
import '../providers/attendance_queue_controller.dart';
import '../providers/month_attendance_providers.dart';
import '../widgets/hero_today_card.dart';
import '../widgets/month_calendar.dart';
import '../widgets/pending_sync_banner.dart';

/// The دوامي tab: today's hero, the offline queue, and a month calendar whose
/// cells show each day's state.
class AttendanceTabScreen extends ConsumerStatefulWidget {
  const AttendanceTabScreen({super.key});

  @override
  ConsumerState<AttendanceTabScreen> createState() =>
      _AttendanceTabScreenState();
}

class _AttendanceTabScreenState extends ConsumerState<AttendanceTabScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final today = ref.read(currentLocalDayProvider);
    _month = DateTime(today.year, today.month);
  }

  void _shift(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  Future<void> _refresh() async {
    await Future.wait([
      ref.read(attendanceQueueProvider.notifier).refresh(),
      ref.read(attendanceControllerProvider.notifier).reload(),
    ]);
    ref.invalidate(monthRecordsProvider(_month));
  }

  void _openToday(BuildContext context) {
    final today = ref.read(currentLocalDayProvider);
    final days = ref.read(monthDaysProvider(_month)).valueOrNull;
    if (days == null) return;
    for (final d in days) {
      if (d.day == today) {
        showDaySheet(context, d);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(currentLocalDayProvider);
    final currentMonth = DateTime(today.year, today.month);
    final isCurrentMonth = _month == currentMonth;
    final pendingCount = ref.watch(pendingAttendanceCountProvider);
    final days = ref.watch(monthDaysProvider(_month));

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text('دوامي', style: AppTheme.heading1(color: AppColors.text)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'الشهر السابق',
                    onPressed: () => _shift(-1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  Text(
                    arabicMonthYear(_month),
                    style: AppTheme.title(color: AppColors.text),
                  ),
                  IconButton(
                    tooltip: 'الشهر التالي',
                    onPressed: isCurrentMonth ? null : () => _shift(1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (isCurrentMonth) ...[
                HeroTodayCard(
                  compact: true,
                  onOpenDay: () => _openToday(context),
                ),
                const SizedBox(height: 14),
              ],
              if (pendingCount > 0) ...[
                PendingSyncBanner(count: pendingCount),
                const SizedBox(height: 14),
              ],
              CardSlot<List<DayEntry>>(
                value: days,
                subject: 'تقويم الدوام',
                skeletonHeight: 320,
                onRetry: () => ref.invalidate(monthRecordsProvider(_month)),
                builder: (list) => _MonthBody(
                  month: _month,
                  days: list,
                  onDayTap: (e) => showDaySheet(context, e),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => context.push('/attendance/history'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text('السجل الكامل'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthBody extends StatelessWidget {
  const _MonthBody({
    required this.month,
    required this.days,
    required this.onDayTap,
  });

  final DateTime month;
  final List<DayEntry> days;
  final ValueChanged<DayEntry> onDayTap;

  @override
  Widget build(BuildContext context) {
    final summary = summarizeMonth(days);
    final counts = <DayState, int>{};
    for (final d in days) {
      if (d.state != DayState.future) {
        counts[d.state] = (counts[d.state] ?? 0) + 1;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppColors.rXl),
            border: Border.all(color: AppColors.border),
          ),
          child: MonthCalendar(month: month, days: days, onDayTap: onDayTap),
        ),
        if (counts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final e in counts.entries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusPill.day(e.key),
                    const SizedBox(width: 4),
                    Text(
                      isolateLtr('${e.value}'),
                      style: AppTheme.caption(color: AppColors.text2),
                    ),
                  ],
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppColors.rXl),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _TotalLine(
                label: 'أيام الحضور',
                value: isolateLtr('${summary.presentDays}'),
              ),
              _TotalLine(
                label: 'ساعات العمل',
                value: isolateLtr(formatDuration(summary.worked)),
              ),
              if (summary.incompleteDays > 0)
                _TotalLine(
                  label: 'انصراف ناقص',
                  value: isolateLtr('${summary.incompleteDays}'),
                ),
              if (summary.rejectedDays > 0)
                _TotalLine(
                  label: 'مرفوض',
                  value: isolateLtr('${summary.rejectedDays}'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: AppTheme.bodyS(color: AppColors.text2)),
          ),
          Text(value, style: AppTheme.label(color: AppColors.text)),
        ],
      ),
    );
  }
}
