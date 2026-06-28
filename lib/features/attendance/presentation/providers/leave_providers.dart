import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_failure.dart';
import '../../data/leave_repository.dart';
import '../../domain/leave.dart';

// ═══════════════════════════════════════════════════════════════════════
//  SIMPLE READS — balance & managers
// ═══════════════════════════════════════════════════════════════════════

/// The authenticated user's leave balance. Re-fetched on `ref.invalidate`
/// (e.g. after submitting a request).
final leaveBalanceProvider = FutureProvider.autoDispose<LeaveBalance>((ref) {
  return ref.watch(leaveRepositoryProvider).balance();
});

/// Managers available to approve a leave request — drives the form dropdown.
final leaveManagersProvider =
    FutureProvider.autoDispose<List<LeaveManager>>((ref) {
  return ref.watch(leaveRepositoryProvider).managers();
});

/// The user's approved leave request covering today, if any — used by the
/// attendance screen to surface an "إجازة معتمدة" status. Null when the user
/// isn't on approved leave today (or the lookup fails).
final approvedLeaveTodayProvider =
    FutureProvider.autoDispose<LeaveRequest?>((ref) async {
  try {
    final requests = await ref.watch(leaveRepositoryProvider).myRequests(
          status: LeaveStatusFilter.approved,
          year: DateTime.now().year,
        );
    final today = DateTime.now();
    for (final r in requests) {
      if (r.isApproved && r.coversDate(today)) return r;
    }
    return null;
  } on ApiFailure {
    // Non-critical surface — fail quiet, the rest of the screen still works.
    return null;
  }
});

// ═══════════════════════════════════════════════════════════════════════
//  LIST STATE (shared by "my requests" and "approvals")
// ═══════════════════════════════════════════════════════════════════════

class LeaveListState {
  const LeaveListState({
    this.requests = const [],
    this.statusFilter = LeaveStatusFilter.all,
    this.isLoading = false,
    this.isRefreshing = false,
    this.hasLoadedOnce = false,
    this.reviewingIds = const {},
    this.error,
  });

  final List<LeaveRequest> requests;
  final LeaveStatusFilter statusFilter;
  final bool isLoading;
  final bool isRefreshing;
  final bool hasLoadedOnce;

  /// Ids currently being approved/rejected — drives per-row spinners.
  final Set<int> reviewingIds;
  final ApiFailure? error;

  bool get isEmpty =>
      requests.isEmpty && !isLoading && !isRefreshing && error == null;

  LeaveListState copyWith({
    List<LeaveRequest>? requests,
    LeaveStatusFilter? statusFilter,
    bool? isLoading,
    bool? isRefreshing,
    bool? hasLoadedOnce,
    Set<int>? reviewingIds,
    ApiFailure? error,
    bool clearError = false,
  }) => LeaveListState(
    requests: requests ?? this.requests,
    statusFilter: statusFilter ?? this.statusFilter,
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    hasLoadedOnce: hasLoadedOnce ?? this.hasLoadedOnce,
    reviewingIds: reviewingIds ?? this.reviewingIds,
    error: clearError ? null : (error ?? this.error),
  );
}

// ═══════════════════════════════════════════════════════════════════════
//  MY REQUESTS
// ═══════════════════════════════════════════════════════════════════════

class MyLeaveRequestsController extends StateNotifier<LeaveListState> {
  MyLeaveRequestsController(this._repo) : super(const LeaveListState()) {
    load();
  }

  final LeaveRepository _repo;

  Future<void> load() async {
    state = state.copyWith(isLoading: !state.hasLoadedOnce, clearError: true);
    await _fetch();
  }

  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true, clearError: true);
    await _fetch();
  }

  Future<void> _fetch() async {
    try {
      final list = await _repo.myRequests(status: state.statusFilter);
      if (!mounted) return;
      state = state.copyWith(
        requests: list,
        isLoading: false,
        isRefreshing: false,
        hasLoadedOnce: true,
      );
    } on ApiFailure catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        hasLoadedOnce: true,
        error: e,
      );
    }
  }

  Future<void> setStatusFilter(LeaveStatusFilter filter) async {
    if (state.statusFilter == filter) return;
    state = state.copyWith(statusFilter: filter, requests: const []);
    await load();
  }
}

final myLeaveRequestsProvider =
    StateNotifierProvider<MyLeaveRequestsController, LeaveListState>((ref) {
  return MyLeaveRequestsController(ref.watch(leaveRepositoryProvider));
});

// ═══════════════════════════════════════════════════════════════════════
//  APPROVALS (manager-facing)
// ═══════════════════════════════════════════════════════════════════════

class LeaveApprovalsController extends StateNotifier<LeaveListState> {
  LeaveApprovalsController(this._repo)
      : super(const LeaveListState(statusFilter: LeaveStatusFilter.pending)) {
    load();
  }

  final LeaveRepository _repo;

  Future<void> load() async {
    state = state.copyWith(isLoading: !state.hasLoadedOnce, clearError: true);
    await _fetch();
  }

  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true, clearError: true);
    await _fetch();
  }

  Future<void> _fetch() async {
    try {
      final list = await _repo.approvals(status: state.statusFilter);
      if (!mounted) return;
      state = state.copyWith(
        requests: list,
        isLoading: false,
        isRefreshing: false,
        hasLoadedOnce: true,
      );
    } on ApiFailure catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        hasLoadedOnce: true,
        error: e,
      );
    }
  }

  Future<void> setStatusFilter(LeaveStatusFilter filter) async {
    if (state.statusFilter == filter) return;
    state = state.copyWith(statusFilter: filter, requests: const []);
    await load();
  }

  /// Approves or rejects [id]. Returns the updated request on success, or
  /// throws [ApiFailure] so the caller can show the error.
  Future<LeaveRequest> review(int id, LeaveStatus status) async {
    state = state.copyWith(reviewingIds: {...state.reviewingIds, id});
    try {
      final updated = await _repo.review(id: id, status: status);
      if (!mounted) return updated;
      // Reflect the new status in place; if the active filter no longer
      // matches, drop it from the visible list.
      final stillVisible = state.statusFilter == LeaveStatusFilter.all ||
          state.statusFilter.apiValue == updated.status.apiValue;
      final next = <LeaveRequest>[];
      for (final r in state.requests) {
        if (r.id == id) {
          if (stillVisible) next.add(updated);
        } else {
          next.add(r);
        }
      }
      state = state.copyWith(
        requests: next,
        reviewingIds: {...state.reviewingIds}..remove(id),
      );
      return updated;
    } on ApiFailure {
      if (mounted) {
        state =
            state.copyWith(reviewingIds: {...state.reviewingIds}..remove(id));
      }
      rethrow;
    }
  }
}

final leaveApprovalsProvider =
    StateNotifierProvider<LeaveApprovalsController, LeaveListState>((ref) {
  return LeaveApprovalsController(ref.watch(leaveRepositoryProvider));
});

// ═══════════════════════════════════════════════════════════════════════
//  LOOKUP — resolve a request id (e.g. from a notification) to a model
// ═══════════════════════════════════════════════════════════════════════

/// Best-effort lookup of a request already loaded into either list. The
/// detail screen triggers a refresh of both lists when this returns null
/// (cold start from a terminated-app notification tap).
final leaveRequestByIdProvider =
    Provider.autoDispose.family<LeaveRequest?, int>((ref, id) {
  for (final r in ref.watch(myLeaveRequestsProvider).requests) {
    if (r.id == id) return r;
  }
  for (final r in ref.watch(leaveApprovalsProvider).requests) {
    if (r.id == id) return r;
  }
  return null;
});
