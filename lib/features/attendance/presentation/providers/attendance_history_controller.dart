import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_failure.dart';
import '../../data/attendance_repository.dart';
import '../../domain/attendance_record.dart';

/// Listing state for the attendance-history screen: paginated records
/// plus an optional date-range filter (`from`/`to`).
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
  final ApiFailure? error;

  bool get isEmpty =>
      records.isEmpty && !isRefreshing && !isLoadingMore && error == null;
  bool get hasMore => currentPage < lastPage;
  bool get hasFilter => from != null || to != null;

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
    from: from,
    to: to,
    error: clearError ? null : (error ?? this.error),
  );
}

class AttendanceHistoryController extends StateNotifier<AttendanceHistoryState> {
  AttendanceHistoryController(this._repo) : super(const AttendanceHistoryState()) {
    refresh();
  }

  final AttendanceRepository _repo;

  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true, clearError: true);
    try {
      final page = await _repo.myRecords(
        from: state.from,
        to: state.to,
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

  /// Replaces the date-range filter and reloads from page 1.
  Future<void> applyFilter({DateTime? from, DateTime? to}) async {
    state = AttendanceHistoryState(from: from, to: to);
    await refresh();
  }

  Future<void> clearFilter() => applyFilter();
}

final attendanceHistoryProvider = StateNotifierProvider.autoDispose<
    AttendanceHistoryController, AttendanceHistoryState>(
  (ref) => AttendanceHistoryController(ref.watch(attendanceRepositoryProvider)),
);
