import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_failure.dart';
import '../../data/notifications_repository.dart';
import '../../domain/notification_model.dart';

// ─── List state ──────────────────────────────────────────────────────

class NotificationsListState {
  const NotificationsListState({
    this.notifications = const [],
    this.currentPage = 0,
    this.lastPage = 1,
    this.total = 0,
    this.isLoadingFirstPage = false,
    this.isLoadingMore = false,
    this.isRefreshing = false,
    this.isMarkingAllRead = false,
    this.error,
  });

  final List<AppNotification> notifications;
  final int currentPage;
  final int lastPage;
  final int total;
  final bool isLoadingFirstPage;
  final bool isLoadingMore;
  final bool isRefreshing;
  final bool isMarkingAllRead;
  final ApiFailure? error;

  bool get isEmpty =>
      notifications.isEmpty &&
      !isLoadingFirstPage &&
      !isRefreshing &&
      error == null;

  bool get hasMore => currentPage < lastPage;

  int get unreadCount => notifications.where((n) => n.isUnread).length;

  NotificationsListState copyWith({
    List<AppNotification>? notifications,
    int? currentPage,
    int? lastPage,
    int? total,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    bool? isRefreshing,
    bool? isMarkingAllRead,
    ApiFailure? error,
    bool clearError = false,
  }) =>
      NotificationsListState(
        notifications: notifications ?? this.notifications,
        currentPage: currentPage ?? this.currentPage,
        lastPage: lastPage ?? this.lastPage,
        total: total ?? this.total,
        isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        isMarkingAllRead: isMarkingAllRead ?? this.isMarkingAllRead,
        error: clearError ? null : (error ?? this.error),
      );
}

// ─── List controller ─────────────────────────────────────────────────

class NotificationsListController
    extends StateNotifier<NotificationsListState> {
  NotificationsListController(this._repo)
      : super(const NotificationsListState()) {
    refresh();
  }

  final NotificationsRepository _repo;

  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true, clearError: true);
    try {
      final page = await _repo.list(page: 1);
      if (!mounted) return;
      state = NotificationsListState(
        notifications: page.notifications,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isRefreshing: false,
        isLoadingFirstPage: false,
        error: e is ApiFailure ? e : null,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final page = await _repo.list(page: state.currentPage + 1);
      if (!mounted) return;
      state = state.copyWith(
        notifications: [...state.notifications, ...page.notifications],
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
        isLoadingMore: false,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoadingMore: false,
        error: e is ApiFailure ? e : null,
      );
    }
  }

  /// Mark a single notification as read — optimistic local update,
  /// then fire the API call.
  Future<void> markAsRead(int id) async {
    final updated = <AppNotification>[];
    for (final n in state.notifications) {
      if (n.id == id && n.isUnread) {
        updated.add(n.markAsRead());
      } else {
        updated.add(n);
      }
    }
    state = state.copyWith(notifications: updated);

    try {
      await _repo.markAsRead(id);
    } on Exception {
      // Silently fail — the item is already marked locally. A refresh
      // will re-sync from the server.
    }
  }

  /// Mark every notification as read — optimistic local update,
  /// then fire the API call.
  Future<void> markAllAsRead() async {
    // Optimistically mark all items in local state FIRST.
    final updated =
        state.notifications.map((n) => n.markAsRead()).toList();
    state = state.copyWith(
      notifications: updated,
      isMarkingAllRead: false,
    );

    try {
      await _repo.markAllAsRead();
    } on Exception {
      // Silently fail — items are already marked locally. A refresh
      // will re-sync from the server.
    }
  }
}

final notificationsListProvider = StateNotifierProvider.autoDispose<
    NotificationsListController, NotificationsListState>(
  (ref) => NotificationsListController(
    ref.watch(notificationsRepositoryProvider),
  ),
);

// ─── Unread-count provider ───────────────────────────────────────────

/// Derives the unread count directly from the notifications list state.
/// This means the bell badge updates instantly when markAsRead or
/// markAllAsRead updates the local state — no extra API call needed.
final unreadCountProvider = Provider.autoDispose<int>((ref) {
  final state = ref.watch(notificationsListProvider);
  return state.unreadCount;
});