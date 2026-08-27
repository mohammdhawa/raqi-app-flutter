import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_failure.dart';
import '../../data/attendance_repository.dart';
import '../../domain/attendance_record.dart';

/// Listing state for the attendance-history screen: paginated records plus
/// the filters — a date range (`from`/`to`) and the refused-only switch.
class AttendanceHistoryState {
  const AttendanceHistoryState({
    this.records = const [],
    this.currentPage = 0,
    this.lastPage = 1,
    this.total = 0,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.from,
    this.to,
    this.rejectedOnly = false,
    this.error,
  });

  final List<AttendanceRecord> records;
  final int currentPage;
  final int lastPage;
  final int total;
  final bool isRefreshing;
  final bool isLoadingMore;
  final DateTime? from;
  final DateTime? to;

  /// Only rows HR refused (`rejected=1`). Off means no `rejected` parameter
  /// at all — refused and standing rows together, which is the default view.
  final bool rejectedOnly;

  final ApiFailure? error;

  bool get isEmpty =>
      records.isEmpty && !isRefreshing && !isLoadingMore && error == null;
  bool get hasMore => currentPage < lastPage;
  bool get hasDateFilter => from != null || to != null;
  bool get hasFilter => hasDateFilter || rejectedOnly;

  AttendanceHistoryState copyWith({
    List<AttendanceRecord>? records,
    int? currentPage,
    int? lastPage,
    int? total,
    bool? isRefreshing,
    bool? isLoadingMore,
    ApiFailure? error,
    bool clearError = false,
  }) => AttendanceHistoryState(
    records: records ?? this.records,
    currentPage: currentPage ?? this.currentPage,
    lastPage: lastPage ?? this.lastPage,
    total: total ?? this.total,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    // Filters are never changed by a copyWith — they are replaced wholesale
    // by applyFilter, which restarts the listing from page 1.
    from: from,
    to: to,
    rejectedOnly: rejectedOnly,
    error: clearError ? null : (error ?? this.error),
  );
}

class AttendanceHistoryController extends StateNotifier<AttendanceHistoryState> {
  /// [initialDate] narrows the first load to a single day — how an
  /// `attendance_rejected` notification opens the history on the day it is
  /// about. Applied before the first fetch rather than after, so the screen
  /// never shows an unfiltered page it then has to replace.
  AttendanceHistoryController(this._repo, {DateTime? initialDate})
      : super(
          initialDate == null
              ? const AttendanceHistoryState()
              : AttendanceHistoryState(from: initialDate, to: initialDate),
        ) {
    refresh();
  }

  final AttendanceRepository _repo;

  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true, clearError: true);
    try {
      final page = await _repo.myRecords(
        from: state.from,
        to: state.to,
        rejected: state.rejectedOnly ? true : null,
        page: 1,
      );
      if (!mounted) return;
      state = AttendanceHistoryState(
        records: page.records,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
        from: state.from,
        to: state.to,
        rejectedOnly: state.rejectedOnly,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isRefreshing: false,
        error: e is ApiFailure ? e : null,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final page = await _repo.myRecords(
        from: state.from,
        to: state.to,
        rejected: state.rejectedOnly ? true : null,
        page: state.currentPage + 1,
      );
      if (!mounted) return;
      state = state.copyWith(
        records: [...state.records, ...page.records],
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

  /// Replaces the filters and reloads from page 1. Omitted arguments are
  /// cleared, not kept — the callers below pass the whole filter set.
  Future<void> applyFilter({
    DateTime? from,
    DateTime? to,
    bool rejectedOnly = false,
  }) async {
    state = AttendanceHistoryState(
      from: from,
      to: to,
      rejectedOnly: rejectedOnly,
    );
    await refresh();
  }

  /// Flips the refused-only filter, keeping the date range in place.
  Future<void> toggleRejectedOnly() => applyFilter(
        from: state.from,
        to: state.to,
        rejectedOnly: !state.rejectedOnly,
      );

  /// Replaces the date range, keeping the refused-only filter in place.
  Future<void> applyDateRange({DateTime? from, DateTime? to}) => applyFilter(
        from: from,
        to: to,
        rejectedOnly: state.rejectedOnly,
      );

  Future<void> clearFilter() => applyFilter();
}

/// Keyed by the day the screen was opened on (`null` for the normal entry
/// point), so a notification tap can land straight on the right day.
final attendanceHistoryProvider = StateNotifierProvider.autoDispose.family<
    AttendanceHistoryController, AttendanceHistoryState, DateTime?>(
  (ref, initialDate) => AttendanceHistoryController(
    ref.watch(attendanceRepositoryProvider),
    initialDate: initialDate,
  ),
);
