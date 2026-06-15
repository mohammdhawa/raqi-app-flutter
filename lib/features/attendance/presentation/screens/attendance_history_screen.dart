import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/errors/api_failure.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../domain/attendance_record.dart';
import '../providers/attendance_history_controller.dart';

/// Full attendance history: paginated `/attendance/my-records`, grouped by
/// day (اليوم / أمس / date) with an optional date-range filter — mirrors
/// the notifications screen's grouped-list layout and AppBar pattern.
class AttendanceHistoryScreen extends ConsumerStatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  ConsumerState<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState
    extends ConsumerState<AttendanceHistoryScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      ref.read(attendanceHistoryProvider.notifier).loadMore();
    }
  }

  Future<void> _pickDateRange() async {
    final current = ref.read(attendanceHistoryProvider);
    final now = DateTime.now();
    final initial = (current.from != null && current.to != null)
        ? DateTimeRange(start: current.from!, end: current.to!)
        : null;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: initial,
      locale: const Locale('ar'),
      builder: (ctx, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
    );
    if (picked == null || !mounted) return;
    await ref
        .read(attendanceHistoryProvider.notifier)
        .applyFilter(from: picked.start, to: picked.end);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(attendanceHistoryProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'سجل الحضور والانصراف',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: _FilterButton(active: state.hasFilter, onTap: _pickDateRange),
          ),
          actions: [
            IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.text,
                size: 20,
              ),
            ),
          ],
        ),
        body: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(AttendanceHistoryState state) {
    if (state.isRefreshing && state.records.isEmpty) {
      return const AlraqiLoading();
    }

    if (state.error != null && state.records.isEmpty) {
      if (state.error!.code == ApiErrorCode.forbidden) {
        return const EmptyStateView(
          icon: Icons.lock_outline,
          title: 'غير مصرح',
          subtitle: 'ليس لديك صلاحية لعرض سجلات الحضور.',
        );
      }
      return ErrorStateView(
        failure: state.error!,
        onRetry: () => ref.read(attendanceHistoryProvider.notifier).refresh(),
      );
    }

    if (state.isEmpty) {
      return EmptyStateView(
        icon: Icons.event_busy_outlined,
        title: state.hasFilter
            ? 'لا توجد سجلات ضمن هذا النطاق'
            : 'لا توجد سجلات حتى الآن',
        subtitle: state.hasFilter
            ? 'جرّب تغيير نطاق التواريخ المحدد.'
            : 'ستظهر هنا سجلات الحضور والانصراف بعد أول تسجيل.',
        action: state.hasFilter
            ? TextButton(
                onPressed: () =>
                    ref.read(attendanceHistoryProvider.notifier).clearFilter(),
                child: const Text('إزالة عامل التصفية'),
              )
            : null,
      );
    }

    final grouped = _groupByDate(state.records);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => ref.read(attendanceHistoryProvider.notifier).refresh(),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (state.hasFilter)
            SliverToBoxAdapter(
              child: _FilterBanner(
                from: state.from!,
                to: state.to!,
                onClear: () =>
                    ref.read(attendanceHistoryProvider.notifier).clearFilter(),
              ),
            ),

          for (final entry in grouped.entries) ...[
            SliverToBoxAdapter(child: _DateHeader(label: entry.key)),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _HistoryRecordTile(record: entry.value[index]),
                ),
                childCount: entry.value.length,
              ),
            ),
          ],

          if (state.isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }

  /// Groups records into labelled buckets: اليوم / أمس / date string —
  /// mirrors `_groupByDate` in notifications_screen.dart.
  Map<String, List<AttendanceRecord>> _groupByDate(
    List<AttendanceRecord> items,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final Map<String, List<AttendanceRecord>> groups = {};
    for (final r in items) {
      final date = DateTime(
        r.recordedAt.year,
        r.recordedAt.month,
        r.recordedAt.day,
      );
      String label;
      if (date == today) {
        label = 'اليوم';
      } else if (date == yesterday) {
        label = 'أمس';
      } else {
        label = DateFormat('yyyy/MM/dd').format(date);
      }
      groups.putIfAbsent(label, () => []).add(r);
    }
    return groups;
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  FILTER CONTROLS
// ═══════════════════════════════════════════════════════════════════════

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.tune, color: AppColors.text2, size: 20),
          ),
          if (active)
            Positioned(
              top: -2,
              left: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterBanner extends StatelessWidget {
  const _FilterBanner({
    required this.from,
    required this.to,
    required this.onClear,
  });

  final DateTime from;
  final DateTime to;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy/MM/dd');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentTint,
        borderRadius: BorderRadius.circular(AppColors.rLg),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_outlined, color: AppColors.accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'من ${fmt.format(from)} إلى ${fmt.format(to)}',
              style: AppTheme.bodyS(),
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close_rounded, color: AppColors.text2, size: 18),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  SECTION HEADER
// ═══════════════════════════════════════════════════════════════════════

/// Section header: "اليوم", "أمس", or a date string.
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.text2,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.end,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  RECORD TILE
// ═══════════════════════════════════════════════════════════════════════

class _HistoryRecordTile extends StatelessWidget {
  const _HistoryRecordTile({required this.record});

  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final isCheckIn = record.type == AttendanceType.checkIn;
    final tint = isCheckIn ? AppColors.approved : AppColors.text2;
    final selfieUrl = record.selfieUrl;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.rLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppColors.rMd),
            child: SizedBox(
              width: 52,
              height: 52,
              child: selfieUrl != null
                  ? CachedNetworkImage(
                      imageUrl: selfieUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: AppColors.surface2),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.surface2,
                        child: const Icon(
                          Icons.person_outline,
                          color: AppColors.text3,
                          size: 22,
                        ),
                      ),
                    )
                  : Container(
                      color: AppColors.surface2,
                      child: const Icon(
                        Icons.person_outline,
                        color: AppColors.text3,
                        size: 22,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(record.type.arabicLabel, style: AppTheme.label()),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('HH:mm').format(record.recordedAt),
                  style: AppTheme.captionS(color: AppColors.text2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
