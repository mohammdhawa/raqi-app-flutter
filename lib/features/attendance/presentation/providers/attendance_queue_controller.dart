import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/attendance_local_db.dart';
import '../../data/selfie_storage.dart';
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

  /// Removes a queued record from SQLite and the in-memory list — used to
  /// dismiss a server-rejected (failed) entry once the user has seen why.
  Future<void> dismiss(int id) async {
    final userId = _userId;
    if (userId == null) return;
    String? selfiePath;
    for (final r in state) {
      if (r.id == id) {
        selfiePath = r.selfiePath;
        break;
      }
    }
    await _db.delete(id, userId);
    // The row is gone for good, so its persisted selfie is unreachable —
    // clean it up best-effort; a failed delete must not block the dismissal.
    if (selfiePath != null) {
      deleteSelfieQuietly(await resolveSelfiePath(selfiePath));
    }
    if (!mounted) return;
    state = [for (final r in state) if (r.id != id) r];
  }

  /// Discards every still-`pending` record (and its selfie) for this user.
  /// Escape hatch for a queue the server will never accept — e.g. records
  /// stranded pending by a server-side account/permission problem, which no
  /// number of retries can clear. Unlike [dismiss] (one server-rejected
  /// `failed` entry), this drops the whole pending backlog at once. The
  /// records are unrecoverable at this point, so this is data the device can
  /// no longer get onto the server regardless.
  Future<void> discardPending() async {
    final userId = _userId;
    if (userId == null) return;
    final pending = [for (final r in state) if (r.isPending) r];
    for (final r in pending) {
      if (r.id == null) continue;
      await _db.delete(r.id!, userId);
      // Row is gone for good — reclaim its persisted selfie best-effort.
      deleteSelfieQuietly(await resolveSelfiePath(r.selfiePath));
    }
    if (!mounted) return;
    state = [for (final r in state) if (!r.isPending) r];
  }

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

/// Records still waiting to reach the server (`pending`) — drives the
/// "بانتظار المزامنة" banner. Excludes `failed` ones: those were rejected
/// by the server and aren't retried, so they're surfaced separately.
final pendingAttendanceCountProvider = Provider<int>((ref) {
  final queue = ref.watch(attendanceQueueProvider);
  return queue.where((r) => r.isPending).length;
});
