import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_failure.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/leave_repository.dart';
import '../../data/leave_type_cache.dart';
import '../../domain/leave.dart';

// ═══════════════════════════════════════════════════════════════════════
//  SIMPLE READS — balance, types & managers
// ═══════════════════════════════════════════════════════════════════════

/// The authenticated user's leave balance. Re-fetched on `ref.invalidate`
/// (e.g. after submitting a request).
///
/// Never cache the figures it returns across a mutation: `used_days` and
/// `remaining_days` are derived server-side from approved requests, so only
/// the latest response is right.
final leaveBalanceProvider = FutureProvider.autoDispose<LeaveBalance>((ref) {
  return ref.watch(leaveRepositoryProvider).balance();
});

/// The leave types the signed-in employee may request, in the backend's own
/// order.
///
/// Fetched fresh on every (re)build and mirrored into [LeaveTypeCache]; the
/// cache is consulted only when the network read fails, so a picker opened
/// offline still offers the real vocabulary instead of nothing. With neither,
/// the failure propagates and the form refuses to submit — an untyped request
/// would be charged to the balance.
///
/// Not autoDispose: the vocabulary is reference data shared by the form and
/// the request lists, and re-fetching it on every screen entry is waste. It
/// is therefore scoped to the authenticated user **explicitly**: without that
/// dependency the list would survive a sign-out on a shared device and the
/// next person to open the form would be offered the previous account's
/// types, straight from memory, with no request the server could refuse.
/// Watching the id means login, logout and a forced 401 logout each rebuild
/// it; the id is also the cache key, so the offline path is scoped the same
/// way.
///
/// Invalidate it to refresh (pull-to-refresh, or a 422 naming a type the
/// server does not offer — which means this list is stale).
final leaveTypesProvider = FutureProvider<List<LeaveType>>((ref) async {
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  // Signed out: no vocabulary, and nothing to fetch it with. Empty rather
  // than stale — there is no leave to file without a session either.
  if (userId == null) return const [];

  final repo = ref.watch(leaveRepositoryProvider);
  final cache = ref.watch(leaveTypeCacheProvider);
  const form = LeaveTypeForm.requests;

  try {
    final types = await repo.leaveTypes(form: form);
    await cache.save(userId, form, types);
    return types;
  } on ApiFailure {
    final cached = await cache.read(userId, form);
    if (cached.isNotEmpty) return cached;
    rethrow;
  }
});

/// Looks a type up by id in the loaded vocabulary — used to label a request
/// row whose stored `leave_type` string is empty. Null while the list is
/// still loading, when it failed to load, or when the id belongs to a type
/// since retired (retired types stay on old rows but leave the picker).
final leaveTypeByIdProvider =
    Provider.autoDispose.family<LeaveType?, int?>((ref, id) {
  if (id == null) return null;
  final types = ref.watch(leaveTypesProvider).valueOrNull;
  if (types == null) return null;
  for (final t in types) {
    if (t.id == id) return t;
  }
  return null;
});

/// Managers and chiefs available to approve a leave request — drives the form
/// picker without dropping chiefs, who commonly close the ordered chain.
///
/// The authenticated user is removed from the list. `/attendance/leave-managers`
/// is a company-wide roster, so a manager or the chief finds THEMSELVES in it;
/// naming yourself as your own approver used to produce a request you could
/// then approve single-handed. The backend now rejects the matching
/// `approver_ids.N`, so leaving it selectable only offers a choice guaranteed
/// to come back as a 422.
final leaveManagersProvider =
    FutureProvider.autoDispose<List<LeaveManager>>((ref) async {
  final currentUserId = ref.watch(currentUserProvider)?.id;
  final managers = await ref.watch(leaveRepositoryProvider).managers();
  if (currentUserId == null) return managers;
  return managers.where((m) => m.id != currentUserId).toList();
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
  }) =>
      LeaveListState(
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

/// Best-effort lookup of a request already loaded into either list — an
/// instant hit when the user reached the detail screen by tapping a row.
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

/// Resolves a request for the detail screen, however the user got there.
///
/// The loaded lists are consulted first, but they cannot be the answer on
/// their own: both carry a status filter the user chose, so someone left on
/// «قيد الانتظار» who taps an approved / rejected / HR-excuse notification
/// would find their request filtered out and be told it does not exist. When
/// the lists miss, this refetches **unfiltered** — status-agnostic, and
/// independent of whatever the lists are showing.
///
/// There is no `GET /attendance/leave-requests/{id}` on the backend, so the
/// fallback **pages through** each listing until the row turns up or the
/// paginator runs out. A single page would not do: the lists are ordered
/// `created_at desc`, and an old request can be reviewed — or excused — today
/// and send a notification while sitting far down the list.
///
/// Only a `403` from the approvals queue is swallowed, and only because it is
/// an answer rather than a failure ("not yours to review"). Anything else —
/// a timeout, a 500 — is rethrown, so the screen offers a retry instead of
/// telling the employee their request does not exist.
final leaveRequestDetailProvider =
    FutureProvider.autoDispose.family<LeaveRequest?, int>((ref, id) async {
  final cached = ref.watch(leaveRequestByIdProvider(id));
  if (cached != null) return cached;

  final repo = ref.watch(leaveRepositoryProvider);

  final mine = await _findInListing(
    id,
    (page) => repo.myRequestsPage(
      perPage: LeaveRepository.maxPerPage,
      page: page,
    ),
  );
  if (mine != null) return mine;

  // The approvals queue is a second home for the row when the caller is the
  // named approver.
  try {
    return await _findInListing(
      id,
      (page) => repo.approvalsPage(
        perPage: LeaveRepository.maxPerPage,
        page: page,
      ),
    );
  } on ApiFailure catch (failure) {
    final forbidden =
        failure.code == ApiErrorCode.forbidden || failure.statusCode == 403;
    // A plain employee is not an approver — that is the expected answer here
    // and means "not found in this listing", nothing more.
    if (!forbidden) rethrow;
    return null;
  }
});

/// Walks [fetchPage] from page 1 until [id] is found or the paginator says
/// there is nothing left.
///
/// [_lookupPageLimit] bounds a pathological account (or a backend whose
/// `last_page` never settles) rather than the normal case: the row a
/// notification points at is usually on page one, and the loop stops the
/// moment `hasMore` is false.
Future<LeaveRequest?> _findInListing(
  int id,
  Future<LeaveRequestsPage> Function(int page) fetchPage,
) async {
  for (var page = 1; page <= _lookupPageLimit; page++) {
    final result = await fetchPage(page);
    for (final r in result.requests) {
      if (r.id == id) return r;
    }
    if (!result.hasMore || result.requests.isEmpty) break;
  }
  return null;
}

/// At 100 rows a page, ten pages is a thousand requests — far past any real
/// employee's history, and a hard stop on the number of round trips one
/// notification tap can cost.
const int _lookupPageLimit = 10;
