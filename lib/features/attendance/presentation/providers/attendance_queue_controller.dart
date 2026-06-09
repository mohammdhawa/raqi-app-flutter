import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/attendance_local_db.dart';
import '../../domain/pending_attendance_record.dart';

/// Owns the local offline queue: loads it on startup, appends freshly
/// captured check-ins/outs, and reflects status changes made by
/// [AttendanceSyncService] back into the in-memory list (and SQLite).
class AttendanceQueueController extends StateNotifier<List<PendingAttendanceRecord>> {
  AttendanceQueueController(this._db) : super(const []) {
    _load();
  }

  final AttendanceLocalDb _db;

  Future<void> _load() async {
    final records = await _db.getAll();
    if (!mounted) return;
    state = records;
  }

  Future<void> refresh() => _load();

  /// Persists a freshly-captured record locally and adds it to the queue —
  /// called immediately after the user taps check-in/out, before any
  /// network attempt, so it's never lost if the app is killed offline.
  Future<PendingAttendanceRecord> add(PendingAttendanceRecord record) async {
    final saved = await _db.insert(record);
    if (mounted) state = [saved, ...state];
    return saved;
  }

  Future<void> markSynced(int id) =>
      _setStatus(id, AttendanceSyncStatus.synced, clearError: true);

  Future<void> markFailed(int id, String error) =>
      _setStatus(id, AttendanceSyncStatus.failed, errorMessage: error);

  Future<void> _setStatus(
    int id,
    AttendanceSyncStatus status, {
    String? errorMessage,
    bool clearError = false,
  }) async {
    await _db.updateStatus(
      id,
      status: status,
      errorMessage: errorMessage,
      clearError: clearError,
    );
    if (!mounted) return;
    state = [
      for (final r in state)
        if (r.id == id)
          r.copyWith(status: status, errorMessage: errorMessage, clearError: clearError)
        else
          r,
    ];
  }
}

final attendanceQueueProvider =
    StateNotifierProvider<AttendanceQueueController, List<PendingAttendanceRecord>>(
  (ref) => AttendanceQueueController(ref.watch(attendanceLocalDbProvider)),
);

/// Records that haven't reached the server yet (`pending` or `failed`) —
/// drives the pending-queue badge shown to the user.
final pendingAttendanceCountProvider = Provider<int>((ref) {
  final queue = ref.watch(attendanceQueueProvider);
  return queue.where((r) => r.isPending || r.isFailed).length;
});

/// Today's locally-captured records, most recent first — what the
/// attendance screen shows under the check-in/out button.
final todayAttendanceQueueProvider = Provider<List<PendingAttendanceRecord>>((ref) {
  final queue = ref.watch(attendanceQueueProvider);
  final now = DateTime.now();
  return queue.where((r) {
    final d = r.recordedAt;
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }).toList();
});
