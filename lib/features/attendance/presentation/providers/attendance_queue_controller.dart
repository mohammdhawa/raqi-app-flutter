import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/attendance_local_db.dart';
import '../../domain/pending_attendance_record.dart';

/// Owns the local offline queue: loads it on startup, appends freshly
/// captured check-ins/outs, and reflects status changes made by
/// [AttendanceSyncService] back into the in-memory list (and SQLite).
///
/// Scoped to a single [_userId] — the provider below recreates this
/// controller whenever the logged-in user changes, so one account never
/// sees or re-syncs another account's queued records on a shared device.
class AttendanceQueueController extends StateNotifier<List<PendingAttendanceRecord>> {
  AttendanceQueueController(this._db, this._userId) : super(const []) {
    if (_userId != null) _load();
  }

  final AttendanceLocalDb _db;
  final int? _userId;

  Future<void> _load() async {
    final userId = _userId;
    if (userId == null) return;
    final records = await _db.getAll(userId);
    if (!mounted) return;
    state = records;
  }

  Future<void> refresh() => _load();

  /// Persists a freshly-captured record locally and adds it to the queue —
  /// called immediately after the user taps check-in/out, before any
  /// network attempt, so it's never lost if the app is killed offline.
  Future<PendingAttendanceRecord> add(PendingAttendanceRecord record) async {
    final userId = _userId;
    if (userId == null) {
      throw StateError('Cannot queue an attendance record while signed out.');
    }
    final saved = await _db.insert(userId, record);
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
    final userId = _userId;
    if (userId == null) return;
    await _db.updateStatus(
      id,
      userId,
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
  (ref) {
    final userId = ref.watch(currentUserProvider.select((u) => u?.id));
    return AttendanceQueueController(ref.watch(attendanceLocalDbProvider), userId);
  },
);

/// Records that haven't reached the server yet (`pending` or `failed`) —
/// drives the pending-queue badge shown to the user.
final pendingAttendanceCountProvider = Provider<int>((ref) {
  final queue = ref.watch(attendanceQueueProvider);
  return queue.where((r) => r.isPending || r.isFailed).length;
});
