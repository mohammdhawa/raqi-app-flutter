import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/notification_model.dart';
import '../providers/notifications_controller.dart';

/// Full-screen view of a single admin broadcast (`type == "broadcast"`).
///
/// Broadcasts carry only a title + body — there is no document or leave
/// request to open — so tapping one lands here to read the full message.
///
/// The screen resolves the broadcast in two ways:
///  * [initial] is supplied when opened from the in-app notifications list,
///    so the content renders instantly with no flicker.
///  * Otherwise (opened from an FCM push tap) it looks the broadcast up in
///    the notifications list by its stable [broadcastId] — the list refreshes
///    itself on first watch, and broadcasts are recent so they land on page 1.
class BroadcastNotificationScreen extends ConsumerStatefulWidget {
  const BroadcastNotificationScreen({
    super.key,
    required this.broadcastId,
    this.initial,
  });

  /// Stable broadcast id (uuid) from the FCM payload / list field.
  final String broadcastId;

  /// The already-loaded notification, when navigated from the list.
  final AppNotification? initial;

  @override
  ConsumerState<BroadcastNotificationScreen> createState() =>
      _BroadcastNotificationScreenState();
}

class _BroadcastNotificationScreenState
    extends ConsumerState<BroadcastNotificationScreen> {
  bool _markedRead = false;

  /// Finds the matching broadcast in the current list state, falling back to
  /// the [initial] passed in via navigation.
  AppNotification? _resolve(NotificationsListState state) {
    for (final n in state.notifications) {
      if (n.broadcastId == widget.broadcastId) return n;
    }
    return widget.initial;
  }

  /// Marks the broadcast read once, using the resolved server id. Safe to call
  /// repeatedly — the controller no-ops when the row is already read.
  void _markReadOnce(AppNotification notification) {
    if (_markedRead || notification.isRead) return;
    _markedRead = true;
    Future.microtask(() {
      ref
          .read(notificationsListProvider.notifier)
          .markAsRead(notification.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsListProvider);
    final notification = _resolve(state);

    if (notification != null) {
      _markReadOnce(notification);
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: _buildAppBar(context),
        body: _buildBody(context, state, notification),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: const Text(
        'تعميم',
        style: TextStyle(
          color: AppColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
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

  Widget _buildBody(
    BuildContext context,
    NotificationsListState state,
    AppNotification? notification,
  ) {
    if (notification != null) {
      return _BroadcastContent(notification: notification);
    }

    // Still fetching the list — show a spinner while we look for the broadcast.
    if (state.isRefreshing || state.isLoadingFirstPage) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    // List loaded but the broadcast isn't in it (e.g. buried past page 1, or a
    // load error). Offer a way to open the full notifications list.
    return _UnavailableBody(
      onOpenList: () => context.go('/notifications'),
    );
  }
}

/// The rendered broadcast: header icon + title, timestamp, and full body.
class _BroadcastContent extends StatelessWidget {
  const _BroadcastContent({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(AppColors.r2xl),
              border: Border.all(color: AppColors.border),
              boxShadow: AppColors.shCard,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        color: AppColors.accentSoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.campaign_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _BroadcastChip(),
                          const SizedBox(height: 6),
                          Text(
                            notification.title,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: AppColors.text3,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatDateTime(notification.createdAt),
                      style: const TextStyle(
                        color: AppColors.text3,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1, color: AppColors.border),
                ),
                SelectableText(
                  notification.body,
                  style: const TextStyle(
                    color: AppColors.text2,
                    fontSize: 15,
                    height: 1.8,
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

/// Small "تعميم" chip identifying the message as an admin broadcast.
class _BroadcastChip extends StatelessWidget {
  const _BroadcastChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppColors.pill),
      ),
      child: const Text(
        'تعميم',
        style: TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Shown when the broadcast can't be found in the loaded list.
class _UnavailableBody extends StatelessWidget {
  const _UnavailableBody({required this.onOpenList});

  final VoidCallback onOpenList;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.campaign_outlined,
              size: 64,
              color: AppColors.text3.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'تعذّر عرض التعميم',
              style: TextStyle(
                color: AppColors.text2,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'يمكنك الاطلاع عليه من قائمة الإشعارات.',
              style: TextStyle(color: AppColors.text3, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onOpenList,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppColors.rMd),
                ),
              ),
              icon: const Icon(Icons.notifications_none_rounded, size: 18),
              label: const Text('الإشعارات'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats the broadcast timestamp as `d/M/yyyy، HH:mm`.
String _formatDateTime(DateTime dateTime) {
  final hh = dateTime.hour.toString().padLeft(2, '0');
  final mm = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.day}/${dateTime.month}/${dateTime.year}، $hh:$mm';
}
