import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_failure.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/attendance_local_db.dart';
import '../../data/attendance_repository.dart';
import 'attendance_queue_controller.dart';

/// Pushes queued offline attendance records to the backend in the
/// background and keeps the local queue's sync status in sync with it.
///
/// Three triggers call [syncPending]:
///   1. App startup (see `_setupAttendanceSync` in main.dart)
///   2. Immediately after a new check-in/out is captured
///   3. Whenever connectivity is restored (see [listenForConnectivity])
///
/// Each queued entry is processed independently by the backend, so a
/// batch can partially succeed — we map `failed[].index` back to the
/// original queue entries to mark exactly those as `failed`, and mark
/// everything else `synced`.
class AttendanceSyncService {
  AttendanceSyncService(this._ref);

  final Ref _ref;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;

  Future<void> syncPending() async {
    if (_isSyncing) return;
    // Only sync the records owned by whoever is currently signed in —
    // otherwise a previous user's queued check-ins/outs could be uploaded
    // under this user's session.
    final userId = _ref.read(currentUserProvider)?.id;
    if (userId == null) return;

    _isSyncing = true;
    try {
      final db = _ref.read(attendanceLocalDbProvider);
      final unsynced = await db.getUnsynced(userId);
      if (unsynced.isEmpty) return;

      final repo = _ref.read(attendanceRepositoryProvider);
      final queue = _ref.read(attendanceQueueProvider.notifier);

      final AttendanceSyncResult result;
      try {
        result = await repo.sync(unsynced);
      } on ApiFailure catch (e) {
        // No network / server error — leave entries as pending so the
        // next trigger (connectivity restored, app restart) retries them.
        debugPrint('Attendance sync failed (will retry): ${e.message}');
        return;
      }

      final failedByIndex = {for (final f in result.failed) f.index: f.error};
      for (var i = 0; i < unsynced.length; i++) {
        final entry = unsynced[i];
        if (entry.id == null) continue;
        final error = failedByIndex[i];
        if (error != null) {
          await queue.markFailed(entry.id!, error);
        } else {
          await queue.markSynced(entry.id!);
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Starts listening for connectivity changes and triggers a sync
  /// attempt whenever the device regains a network connection.
  /// Idempotent — safe to call multiple times.
  void listenForConnectivity() {
    if (_connectivitySub != null) return;
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) syncPending();
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }
}

final attendanceSyncServiceProvider = Provider<AttendanceSyncService>((ref) {
  final service = AttendanceSyncService(ref);
  ref.onDispose(service.dispose);
  return service;
});
