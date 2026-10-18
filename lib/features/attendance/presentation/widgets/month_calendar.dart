import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/format.dart';
import '../../../../shared/widgets/day_state.dart';
import '../../../../shared/widgets/status_pill.dart';
import '../../domain/attendance_record.dart';
import '../../domain/month_days.dart';
import '../../domain/pending_attendance_record.dart';
import '../providers/attendance_controller.dart';

const _weekdayHeaders = [
  'سبت',
  'أحد',
  'إثنين',
  'ثلاثاء',
  'أربعاء',
  'خميس',
  'جمعة',
];

/// A Saturday-first month grid. Each cell shows the day number and the icon of
/// the day's state; the state is also in the cell's semantics label, so colour
/// is never the only signal.
///
/// The Saturday-first layout is a presentation choice only. Which days are
/// working days is server configuration and is never decided here.
class MonthCalendar extends ConsumerWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.days,
    required this.onDayTap,
  });

  final DateTime month;
  final List<DayEntry> days;
  final ValueChanged<DayEntry> onDayTap;

  static const double _cell = 46;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(currentLocalDayProvider);
    final firstDay = DateTime(month.year, month.month);
    final leading = (firstDay.weekday - DateTime.saturday + 7) % 7;

    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const SizedBox(height: _cell),
      for (final entry in days)
        _DayCell(
          entry: entry,
          isToday: entry.day == today,
          onTap: () => onDayTap(entry),
        ),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox(height: _cell));
    }

    return Column(
      children: [
        Row(
          children: [
            for (final h in _weekdayHeaders)
              Expanded(
                child: Center(
                  child: Text(h, style: AppTheme.caption(color: AppColors.text2)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var r = 0; r < cells.length; r += 7)
          Row(
            children: [
              for (var c = r; c < r + 7; c++) Expanded(child: cells[c]),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.entry,
    required this.isToday,
    required this.onTap,
  });

  final DayEntry entry;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = entry.state;
    final isFuture = state == DayState.future;
    final label = isFuture
        ? arabicWeekdayDayMonth(entry.day)
        : '${arabicWeekdayDayMonth(entry.day)} — ${state.label}';
    final icon = state.icon;

    return Semantics(
      button: true,
      enabled: !isFuture,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: state.bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.rMd),
            side: isToday
                ? const BorderSide(color: AppColors.accent, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppColors.rMd),
            onTap: isFuture ? null : onTap,
            child: SizedBox(
              height: MonthCalendar._cell - 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${entry.day.day}',
                    style: AppTheme.label(color: state.fg),
                  ),
                  if (icon != null) Icon(icon, size: 12, color: state.fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Bottom sheet with everything the app knows about one day.
Future<void> showDaySheet(BuildContext context, DayEntry entry) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppColors.rSheet),
      ),
    ),
    builder: (sheetContext) => _DaySheet(
      entry: entry,
      onOpenHistory: () {
        Navigator.of(sheetContext).pop();
        context.push('/attendance/history?date=${_isoDate(entry.day)}');
      },
    ),
  );
}

class _DaySheet extends StatelessWidget {
  const _DaySheet({required this.entry, required this.onOpenHistory});

  final DayEntry entry;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final state = entry.state;
    // Synced local rows are already shown through their remote twin.
    final pending = entry.pending.where((p) => !p.isSynced).toList();
    final hasRows = entry.records.isNotEmpty || pending.isNotEmpty;
    final showHistory =
        state == DayState.rejected || state == DayState.incomplete;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    arabicWeekdayDayMonth(entry.day),
                    style: AppTheme.heading3(color: AppColors.text),
                  ),
                ),
                if (state != DayState.future) StatusPill.day(state),
              ],
            ),
            const SizedBox(height: 12),
            for (final r in entry.records) _RemoteRow(record: r),
            for (final p in pending) _PendingRow(record: p),
            if (entry.worked > Duration.zero)
              _InfoLine(
                label: 'ساعات العمل',
                value: isolateLtr(formatDuration(entry.worked)),
              ),
            if (entry.leave != null)
              _InfoLine(
                label: entry.leave!.leaveType ?? 'إجازة',
                value: 'معتمدة',
              ),
            if (!hasRows && entry.leave == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'لا يوجد تسجيل لهذا اليوم.',
                  style: AppTheme.bodyS(color: AppColors.text2),
                ),
              ),
            if (showHistory) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onOpenHistory,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text('عرض في السجل'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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

class _RowShell extends StatelessWidget {
  const _RowShell({required this.title, required this.pill, this.detail});
  final String title;
  final Widget pill;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
              Expanded(
                child: Text(title, style: AppTheme.label(color: AppColors.text)),
              ),
              pill,
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(detail!, style: AppTheme.caption(color: AppColors.text2)),
          ],
        ],
      ),
    );
  }
}

class _RemoteRow extends StatelessWidget {
  const _RemoteRow({required this.record});
  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final title =
        '${record.type.arabicLabel} · ${isolateLtr(formatClock(record.recordedAt))}';
    if (record.isRejected) {
      return _RowShell(
        title: title,
        pill: StatusPill.day(DayState.rejected),
        detail: record.rejectionReasonLabel,
      );
    }
    if (record.isMissingCheckout) {
      return _RowShell(title: title, pill: StatusPill.day(DayState.incomplete));
    }
    return _RowShell(
      title: title,
      pill: const StatusPill(
        label: 'مؤكد',
        icon: Icons.check_rounded,
        fg: AppColors.dayPresentText,
        bg: AppColors.dayPresentBg,
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.record});
  final PendingAttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      title:
          '${record.type.arabicLabel} · ${isolateLtr(formatClock(record.recordedAt))}',
      pill: StatusPill.day(DayState.pendingSync),
      detail: record.isFailed ? record.errorMessage : null,
    );
  }
}
