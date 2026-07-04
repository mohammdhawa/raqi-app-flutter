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
/// Sync attempts are triggered by:
///   1. App startup (see `_setupAttendanceSync` in main.dart)
///   2. Immediately after a new check-in/out is captured
///   3. Whenever connectivity is restored (see [listenForConnectivity])
///   4. Returning to the foreground
///
/// Transient failures also schedule retries with bounded exponential backoff,
/// because having Wi-Fi/mobile connectivity does not guarantee internet access.
///
/// Each queued entry is processed independently by the backend, so a
/// batch can partially succeed — we map `failed[].index` back to the
/// original queue entries to mark exactly those as `failed`, and mark
/// everything else `synced`.
class AttendanceSyncService {
  AttendanceSyncService(this._ref);

  final Ref _ref;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _retryTimer;
  bool _isSyncing = false;
  bool _syncRequested = false;
  int _consecutiveFailures = 0;

  static const _retryDelays = <Duration>[
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];

  Future<void> syncPending() async {
    // Preserve a trigger that arrives while an upload is in progress.
    if (_isSyncing) {
      _syncRequested = true;
      return;
    }

    // A direct trigger makes an already scheduled retry redundant.
    _retryTimer?.cancel();
    _retryTimer = null;
    // Only sync the records owned by whoever is currently signed in —
    // otherwise a previous user's queued check-ins/outs could be uploaded
    // under this user's session.
    final userId = _ref.read(currentUserProvider)?.id;
    if (userId == null) return;

    _isSyncing = true;
    try {
      final db = _ref.read(attendanceLocalDbProvider);
      final unsynced = await db.getUnsynced(userId);
      if (unsynced.isEmpty) {
        _consecutiveFailures = 0;
        return;
      }

      final repo = _ref.read(attendanceRepositoryProvider);
      final queue = _ref.read(attendanceQueueProvider.notifier);

      final AttendanceSyncResult result;
      try {
        result = await repo.sync(unsynced);
      } on ApiFailure catch (e) {
        // Leave transient network/server failures pending for a later retry.
        debugPrint('Attendance sync failed (will retry): ${e.message}');
        if (_isTransient(e)) _scheduleRetry();
        return;
      } catch (e) {
        // Anything the repository doesn't map to ApiFailure (unwrapped Dio
        // errors, response parse failures, unreadable selfie files) would
        // otherwise strand records as pending with no retry scheduled.
        debugPrint('Attendance sync failed unexpectedly (will retry): $e');
        _scheduleRetry();
        return;
      }

      _consecutiveFailures = 0;

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
      if (_syncRequested) {
        _syncRequested = false;
        unawaited(syncPending());
      }
    }
  }

  bool _isTransient(ApiFailure failure) {
    final status = failure.statusCode;
    return failure.code == ApiErrorCode.network ||
        failure.code == ApiErrorCode.serverError ||
        (status != null && status >= 500);
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    final index = _consecutiveFailures
        .clamp(0, _retryDelays.length - 1)
        .toInt();
    final delay = _retryDelays[index];
    _consecutiveFailures++;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(syncPending());
    });
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
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}

final attendanceSyncServiceProvider = Provider<AttendanceSyncService>((ref) {
  final service = AttendanceSyncService(ref);
  ref.onDispose(service.dispose);
  return service;
});
