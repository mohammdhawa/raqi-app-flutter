import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_failure.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/attendance_local_db.dart';
import '../../data/attendance_repository.dart';
import '../../data/selfie_storage.dart';
import '../../domain/pending_attendance_record.dart';
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

      // A record whose selfie file no longer exists (aggressive cache
      // cleaners on MIUI etc.) can never upload — building its multipart
      // part would throw before any network call, stranding the whole
      // batch as pending forever. Partition those out FIRST and mark them
      // failed (dismissible), so the remaining records still sync.
      //
      // Paths are resolved against the CURRENT app-support dir (see
      // resolveSelfiePath) so an iOS container-UUID change on app update
      // doesn't make every stored path look missing. Sendable entries carry
      // the resolved absolute path so repo.sync and cleanup use it directly.
      final missing = <PendingAttendanceRecord>[];
      final sendable = <PendingAttendanceRecord>[];
      for (final entry in unsynced) {
        final absolutePath = await resolveSelfiePath(entry.selfiePath);
        if (File(absolutePath).existsSync()) {
          sendable.add(entry.copyWith(selfiePath: absolutePath));
        } else {
          missing.add(entry);
        }
      }

      for (final entry in missing) {
        if (entry.id == null) continue;
        await queue.markFailed(
          entry.id!,
          'تعذّرت المزامنة: لم تعد صورة التسجيل متوفرة على الجهاز. '
          'يرجى تسجيل الحضور مجدداً.',
        );
      }

      if (sendable.isEmpty) {
        // Nothing transient happened — don't POST an empty batch.
        _consecutiveFailures = 0;
        return;
      }

      final AttendanceSyncResult result;
      try {
        result = await repo.sync(sendable);
      } on ApiFailure catch (e) {
        debugPrint('Attendance sync failed: ${e.message}');
        if (_isTransient(e)) {
          // Network/5xx — leave pending and retry with backoff.
          _scheduleRetry();
        } else if (!_isRecoverable(e)) {
          // A deterministic rejection of the whole request (e.g. 413 payload
          // too large, 400/422) will fail identically on every retry and would
          // otherwise wedge the queue forever with no retry and no dismissible
          // tile. Surface the batch as dismissible failures instead. Auth
          // failures are excluded (_isRecoverable) — those clear on re-login.
          for (final entry in sendable) {
            if (entry.id == null) continue;
            await queue.markFailed(
              entry.id!,
              'تعذّرت المزامنة: رفض الخادم هذه السجلات. '
              'يرجى المحاولة مجدداً أو حذفها.',
            );
          }
        }
        return;
      } catch (e) {
        // Anything the repository doesn't map to ApiFailure (unwrapped Dio
        // errors, response parse failures, unreadable selfie files) would
        // otherwise strand records as pending with no retry scheduled.
        debugPrint('Attendance sync failed unexpectedly (will retry): $e');
        _scheduleRetry();
        return;
      }

      // The server's failed[].index points into the records[] we sent —
      // i.e. positions in `sendable`, NOT `unsynced`. Mapping against the
      // full list after filtering would shift indices and flip the wrong
      // records to synced/failed.
      final failedByIndex = {for (final f in result.failed) f.index: f};

      // Not every entry in failed[] is finished with.
      //
      // The endpoint reports two different things through one array: a
      // business rule the entry broke (permanent — re-sending it produces
      // the same rejection forever) and an unexpected server-side failure
      // (transient — the server logged it and the docs call it retryable).
      // Marking both `failed` threw away real check-ins whenever the server
      // hiccuped: `failed` is terminal here, it schedules no retry, and the
      // only thing the employee can do with the tile is dismiss it.
      var hasRetryable = false;
      for (var i = 0; i < sendable.length; i++) {
        final entry = sendable[i];
        if (entry.id == null) continue;
        final failure = failedByIndex[i];

        if (failure == null) {
          await queue.markSynced(entry.id!);
          // getUnsynced only returns pending rows, so a synced record's
          // selfie is never read again — reclaim the storage. entry.selfiePath
          // is the resolved absolute path (set on the sendable copy above).
          deleteSelfieQuietly(entry.selfiePath);
          continue;
        }

        if (failure.isRetryable) {
          // Left `pending`, and its selfie left on disk — the next attempt
          // re-sends it. getUnsynced picks it up again unchanged.
          hasRetryable = true;
          continue;
        }

        await queue.markFailed(entry.id!, failure.error);
      }

      if (hasRetryable) {
        // Keep climbing the backoff ladder rather than resetting it: a
        // server that just failed on some entries is exactly the case the
        // widening delay exists for.
        _scheduleRetry();
      } else {
        _consecutiveFailures = 0;
      }
    } finally {
      _isSyncing = false;
      if (_syncRequested) {
        _syncRequested = false;
        unawaited(syncPending());
      }
    }
  }

  /// Deletes persisted selfies orphaned by a process kill between copy and
  /// queue insert, or between a successful sync and its cleanup. Best-effort;
  /// safe to call on startup. Scans across all users' rows so a shared device
  /// never wipes another account's pending selfie.
  Future<void> sweepOrphanedSelfies() async {
    final userId = _ref.read(currentUserProvider)?.id;
    if (userId == null) return;
    try {
      final db = _ref.read(attendanceLocalDbProvider);
      final referenced = await db.referencedSelfieFileNames(userId);
      await sweepOrphanedSelfieFiles(referenced);
    } catch (_) {
      // Best-effort — a failed sweep must never disrupt startup.
    }
  }

  bool _isTransient(ApiFailure failure) {
    final status = failure.statusCode;
    return failure.code == ApiErrorCode.network ||
        failure.code == ApiErrorCode.serverError ||
        (status != null && status >= 500);
  }

  /// Auth failures clear on re-login, so their records must stay pending (not
  /// be marked terminally failed) — the user-scoped sync will re-send them.
  bool _isRecoverable(ApiFailure failure) =>
      failure.code == ApiErrorCode.unauthenticated ||
      failure.code == ApiErrorCode.forbidden;

  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    final index =
        _consecutiveFailures.clamp(0, _retryDelays.length - 1).toInt();
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
