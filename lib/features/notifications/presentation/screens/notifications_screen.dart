import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/notification_model.dart';
import '../providers/notifications_controller.dart';

/// Full-screen notification centre.
///
/// Layout (RTL):
///  ┌──────────────────────────────────────────┐
///  │  ⋯  [badge]     الإشعارات          ‹    │  AppBar
///  ├──────────────────────────────────────────┤
///  │ N إشعارات غير مقروءة   تعليم الكل … ✓  │  sub-header
///  ├──────────────────────────────────────────┤
///  │  ── اليوم ──                            │  section header
///  │  [notification card]                    │
///  │  [notification card]                    │
///  │  ── أمس ──                              │
///  │  [notification card]                    │
///  │  …                                      │
///  └──────────────────────────────────────────┘
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
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
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    if (currentScroll >= maxScroll - 200) {
      ref.read(notificationsListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsListProvider);
    final unreadCount = state.notifications.where((n) => n.isUnread).length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: _buildAppBar(context, state, unreadCount),
        body: _buildBody(context, state, unreadCount),
      ),
    );
  }

  // ── AppBar ───────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    NotificationsListState state,
    int unreadCount,
  ) {
    return AppBar(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: const Text(
        'الإشعارات',
        style: TextStyle(
          color: AppColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: _MenuButton(unreadCount: unreadCount),
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
    );
  }

  // ── Body ─────────────────────────────────────────────────────────

  Widget _buildBody(
    BuildContext context,
    NotificationsListState state,
    int unreadCount,
  ) {
    if (state.isLoadingFirstPage || (state.isRefreshing && state.notifications.isEmpty)) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (state.error != null && state.notifications.isEmpty) {
      return _ErrorBody(
        message: state.error!.message,
        onRetry: () =>
            ref.read(notificationsListProvider.notifier).refresh(),
      );
    }

    if (state.isEmpty) {
      return const _EmptyBody();
    }

    final grouped = _groupByDate(state.notifications);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () =>
          ref.read(notificationsListProvider.notifier).refresh(),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Sub-header: unread count + mark-all button.
          SliverToBoxAdapter(
            child: _SubHeader(
              unreadCount: unreadCount,
              isMarkingAll: state.isMarkingAllRead,
              onMarkAll: unreadCount > 0
                  ? () => ref
                      .read(notificationsListProvider.notifier)
                      .markAllAsRead()
                  : null,
            ),
          ),

          // Grouped notification cards.
          for (final entry in grouped.entries) ...[
            SliverToBoxAdapter(child: _DateHeader(label: entry.key)),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final notification = entry.value[index];
                  return _NotificationCard(
                    notification: notification,
                    onTap: () => _onNotificationTap(notification),
                  );
                },
                childCount: entry.value.length,
              ),
            ),
          ],

          // Loading-more indicator.
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

          // Bottom padding.
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }

  // ── Tap handler ──────────────────────────────────────────────────

  Future<void> _onNotificationTap(AppNotification notification) async {
    // Mark as read (optimistic).
    ref.read(notificationsListProvider.notifier).markAsRead(notification.id);

    // A checkout reminder deep-links to the check-in/out screen so the user
    // can record the انصراف they forgot.
    if (notification.type == NotificationType.attendanceCheckoutReminder) {
      if (mounted) context.push('/attendance');
      return;
    }

    // Navigate based on the payload. A leave_request_id always wins so leave
    // notifications open the relevant request regardless of `type`.
    final leaveId = notification.leaveRequestId;
    if (leaveId != null) {
      if (mounted) context.push('/attendance/leave/requests/$leaveId');
      return;
    }

    // Likewise, a document_id always wins regardless of `type` — document
    // notifications can arrive as `general` (chip "وارد") yet still carry the
    // id needed to open the document.
    final docId = notification.documentId;
    if (docId != null) {
      if (mounted) {
        context.push('/documents/$docId');
      }
    }
  }

  // ── Date grouping ───────────────────────────────────────────────

  /// Groups notifications into labelled buckets: اليوم / أمس / date string.
  Map<String, List<AppNotification>> _groupByDate(
    List<AppNotification> items,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final Map<String, List<AppNotification>> groups = {};

    for (final n in items) {
      final date = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      String label;
      if (date == today) {
        label = 'اليوم';
      } else if (date == yesterday) {
        label = 'أمس';
      } else {
        label =
            '${n.createdAt.day}/${n.createdAt.month}/${n.createdAt.year}';
      }
      groups.putIfAbsent(label, () => []).add(n);
    }

    return groups;
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  PRIVATE WIDGETS
// ═══════════════════════════════════════════════════════════════════════

/// Three-dot menu button in the leading slot — matches the Figma design.
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppColors.rMd),
          ),
          child: const Icon(
            Icons.more_horiz_rounded,
            color: AppColors.text2,
            size: 20,
          ),
        ),
        if (unreadCount > 0)
          Positioned(
            top: -4,
            left: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppColors.pill),
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Center(
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Sub-header bar showing unread count label and "mark all" button.
class _SubHeader extends StatelessWidget {
  const _SubHeader({
    required this.unreadCount,
    required this.isMarkingAll,
    this.onMarkAll,
  });

  final int unreadCount;
  final bool isMarkingAll;
  final VoidCallback? onMarkAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // Unread count label (right side in RTL).
          Text(
            '$unreadCount إشعارات غير مقروءة',
            style: const TextStyle(
              color: AppColors.text2,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          // Mark-all button (left side in RTL).
          GestureDetector(
            onTap: onMarkAll,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isMarkingAll)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  )
                else
                  const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                const SizedBox(width: 4),
                Text(
                  'تعليم الكل كمقروء',
                  style: TextStyle(
                    color: onMarkAll != null
                        ? AppColors.primary
                        : AppColors.text3,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

/// A single notification card.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isUnread = notification.isUnread;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isUnread ? const Color(0xFFF9FBFF) : AppColors.bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unread dot.
            if (isUnread)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 10),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),

            // Text content.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight:
                          isUnread ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: const TextStyle(
                      color: AppColors.text2,
                      fontSize: 13,
                      height: 1.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        _relativeTime(notification.createdAt),
                        style: const TextStyle(
                          color: AppColors.text3,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '•',
                        style: TextStyle(color: AppColors.text3, fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(type: notification.type),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Type icon.
            _TypeIcon(type: notification.type),
          ],
        ),
      ),
    );
  }
}

/// The circular icon on the left (visually) side of each notification card.
class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.type});

  final NotificationType type;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, IconData icon) = switch (type) {
      NotificationType.approval => (
          AppColors.approvedBg,
          AppColors.approved,
          Icons.check_circle_outline_rounded,
        ),
      NotificationType.rejection => (
          AppColors.rejectedBg,
          AppColors.rejected,
          Icons.cancel_outlined,
        ),
      NotificationType.document => (
          AppColors.pendingBg,
          AppColors.pending,
          Icons.error_outline_rounded,
        ),
      NotificationType.leave => (
          AppColors.accentSoft,
          AppColors.primary,
          Icons.beach_access_outlined,
        ),
      NotificationType.attendanceCheckoutReminder => (
          AppColors.pendingBg,
          AppColors.pending,
          Icons.logout_rounded,
        ),
      NotificationType.general => (
          AppColors.surface2,
          AppColors.text2,
          Icons.description_outlined,
        ),
    };

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: fg, size: 22),
    );
  }
}

/// Small status chip shown next to the time (e.g. "قيد الانتظار", "معتمد").
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.type});

  final NotificationType type;

  @override
  Widget build(BuildContext context) {
    final (String label, Color textColor, Color bgColor) = switch (type) {
      NotificationType.approval => (
          'معتمد',
          AppColors.approvedText,
          AppColors.approvedBg,
        ),
      NotificationType.rejection => (
          'مرفوض',
          AppColors.rejectedText,
          AppColors.rejectedBg,
        ),
      NotificationType.document => (
          'قيد الانتظار',
          AppColors.pendingText,
          AppColors.pendingBg,
        ),
      NotificationType.leave => (
          'إجازة',
          AppColors.primary,
          AppColors.accentSoft,
        ),
      NotificationType.attendanceCheckoutReminder => (
          'تذكير انصراف',
          AppColors.pendingText,
          AppColors.pendingBg,
        ),
      NotificationType.general => (
          'وارد',
          AppColors.primary,
          AppColors.surface2,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppColors.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Error state body with a retry button.
class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 52, color: AppColors.text3),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: AppColors.text2, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppColors.rMd),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state — shown when there are zero notifications.
class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 64,
              color: AppColors.text3.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'لا توجد إشعارات',
              style: TextStyle(
                color: AppColors.text2,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'ستظهر الإشعارات هنا عند وصول تحديثات جديدة.',
              style: TextStyle(color: AppColors.text3, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════════════════════════════

/// Returns a human-readable Arabic relative-time string.
String _relativeTime(DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime);

  if (diff.inSeconds < 60) return 'الآن';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    if (m == 1) return 'منذ دقيقة';
    if (m == 2) return 'منذ دقيقتين';
    if (m <= 10) return 'منذ $m دقائق';
    return 'منذ $m دقيقة';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    if (h == 1) return 'منذ ساعة';
    if (h == 2) return 'منذ ساعتين';
    if (h <= 10) return 'منذ $h ساعات';
    return 'منذ $h ساعة';
  }

  final today = DateTime(now.year, now.month, now.day);
  final dateDay =
      DateTime(dateTime.year, dateTime.month, dateTime.day);
  if (dateDay == today.subtract(const Duration(days: 1))) {
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    return 'أمس، $hh:$mm';
  }

  final hh = dateTime.hour.toString().padLeft(2, '0');
  final mm = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.day}/${dateTime.month}/${dateTime.year}، $hh:$mm';
}