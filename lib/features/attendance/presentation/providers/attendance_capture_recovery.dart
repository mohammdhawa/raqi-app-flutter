import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/error_log.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../data/attendance_local_db.dart';
import '../../data/selfie_storage.dart';
import '../../domain/attendance_capture_draft.dart';
import '../../domain/attendance_record.dart';
import '../../domain/pending_attendance_record.dart';
import 'attendance_queue_controller.dart';
import 'attendance_sync_service.dart';

/// Runs one check-in/out capture bracketed by a durable draft.
///
/// The draft is committed to SQLite BEFORE [captureSelfie] opens the external
/// camera — if it can't be saved, this throws and the camera never opens,
/// because a capture the OS kills mid-camera would then be unrecoverable.
///
/// The draft is cleared once the capture is settled in this process: after
/// the row is queued (the row carries the draft's operation id, so even a
/// kill between queueing and clearing can't lead to a second submission), or
/// on cancel/error. [captureSelfie] returns the persisted selfie path, or
/// null when the user cancelled. Returns the queued record, or null on cancel.
Future<PendingAttendanceRecord?> captureWithDraft({
  required AttendanceLocalDb db,
  required AttendanceCaptureDraft draft,
  required Future<String?> Function() captureSelfie,
  required Future<PendingAttendanceRecord> Function(PendingAttendanceRecord)
      enqueue,
  DateTime Function() now = DateTime.now,
}) async {
  await db.saveCaptureDraft(draft);
  try {
    final selfiePath = await captureSelfie();
    if (selfiePath == null) return null;
    return await enqueue(
      PendingAttendanceRecord(
        type: draft.type,
        latitude: draft.latitude,
        longitude: draft.longitude,
        selfiePath: selfiePath,
        // Unchanged same-process semantics: the moment the photo came back.
        recordedAt: now(),
        operationId: draft.operationId,
      ),
    );
  } finally {
    await _clearDraftQuietly(db, draft);
  }
}

/// A failed clear must not turn a queued capture into a reported failure; the
/// leftover draft is resolved by the next startup's recovery instead.
Future<void> _clearDraftQuietly(
  AttendanceLocalDb db,
  AttendanceCaptureDraft draft,
) async {
  try {
    await db.clearCaptureDraft(draft.operationId, draft.userId);
  } catch (e, stack) {
    logUnexpected('Could not clear attendance capture draft', e, stack);
  }
}

enum AttendanceCaptureOutcome { recovered, incomplete }

/// A one-shot message from startup recovery for the attendance screen.
class AttendanceCaptureNotice {
  const AttendanceCaptureNotice(this.outcome, this.type);

  final AttendanceCaptureOutcome outcome;
  final AttendanceType type;

  bool get isError => outcome == AttendanceCaptureOutcome.incomplete;

  String get message {
    final action =
        type == AttendanceType.checkIn ? 'تسجيل الحضور' : 'تسجيل الانصراف';
    return switch (outcome) {
      AttendanceCaptureOutcome.recovered =>
        'تم استكمال $action بعد إعادة تشغيل التطبيق — جارٍ المزامنة في الخلفية.',
      AttendanceCaptureOutcome.incomplete =>
        'لم يكتمل $action لأن التطبيق أُغلق أثناء التقاط الصورة. '
            'يرجى المحاولة مجدداً.',
    };
  }
}

/// Set by [AttendanceCaptureRecovery]; shown and cleared by the attendance
/// screen. Reset whenever the signed-in user changes, so on a shared device
/// one employee never sees a notice about another's capture.
final attendanceCaptureNoticeProvider =
    StateProvider<AttendanceCaptureNotice?>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return null;
});

/// Completes a check-in/out whose process was killed while the external
/// camera was open.
///
/// On MIUI/HyperOS (seen on a Redmi 14C) the camera "boost" killer SIGKILLs
/// the app while the system camera is in front; confirming the photo then
/// cold-starts a fresh process. image_picker caches that photo for
/// `retrieveLostData`, and the draft written by [captureWithDraft] says what
/// it was for. This pairs them — once per process, after sign-in is known.
class AttendanceCaptureRecovery {
  AttendanceCaptureRecovery(
    this._ref, {
    Future<LostDataResponse> Function()? retrieveLostData,
    bool? isAndroid,
    Future<String> Function(File)? persistSelfie,
    Future<DateTime> Function(String path)? photoTakenAt,
    DateTime Function()? now,
  })  : _retrieveLostData =
            retrieveLostData ?? (() => ImagePicker().retrieveLostData()),
        _isAndroid = isAndroid ?? Platform.isAndroid,
        _persistSelfie = persistSelfie ?? persistSelfieForUpload,
        _photoTakenAt = photoTakenAt ?? ((path) => File(path).lastModified()),
        _now = now ?? DateTime.now;

  final Ref _ref;
  final Future<LostDataResponse> Function() _retrieveLostData;
  final bool _isAndroid;
  final Future<String> Function(File) _persistSelfie;

  /// The picker writes the photo while handling the camera's result, which
  /// happens as soon as the employee confirms it — before Flutter has even
  /// started. Its modification time is therefore the moment the photo came
  /// back, the same moment the same-process path records.
  final Future<DateTime> Function(String path) _photoTakenAt;
  final DateTime Function() _now;

  static const _retrieveLostDataTimeout = Duration(seconds: 10);

  /// The one recovery run of this process, once started. Later callers await
  /// it rather than skipping ahead, so "after recovery" means after it has
  /// finished — not merely after it began.
  Future<void>? _run;

  /// Safe to call on every authenticated transition and before every
  /// capture: only the first call made while signed in does anything; every
  /// call completes once that run has finished. Never throws.
  Future<void> recoverOnce() {
    final running = _run;
    if (running != null) return running;
    final userId = _ref.read(currentUserProvider)?.id;
    // Signed out: leave the picker's cache and the draft for whoever signs in
    // next in this process — a different user's draft is discarded then.
    if (userId == null) return Future.value();
    return _run = _recoverSafely(userId);
  }

  Future<void> _recoverSafely(int userId) async {
    try {
      await _recover(userId);
    } catch (e, stack) {
      logUnexpected('Attendance capture recovery failed', e, stack);
    }
  }

  Future<void> _recover(int userId) async {
    // Taken before the first await: the queue provider follows whoever is
    // signed in, and a capture must land in its owner's queue even if the
    // account changes mid-recovery — it then syncs on their next sign-in.
    final queue = _ref.read(attendanceQueueProvider.notifier);
    final photo = await _recoveredPhoto();
    try {
      final db = _ref.read(attendanceLocalDbProvider);
      final draft = await db.readCaptureDraft(userId);
      final alreadyQueued =
          draft != null && await db.hasOperation(draft.operationId, userId);

      final decision = decideCaptureRecovery(
        draft: draft,
        currentUserId: userId,
        now: _now(),
        recoveredPhoto: photo,
        alreadyQueued: alreadyQueued,
      );

      switch (decision) {
        case CaptureRecoveryNothing():
          return;
        case CaptureRecoveryAlreadyQueued(:final draft) ||
              CaptureRecoveryDiscard(:final draft) ||
              CaptureRecoveryStale(:final draft):
          await _clearDraftQuietly(db, draft);
        case CaptureRecoveryIncomplete(:final draft):
          await _clearDraftQuietly(db, draft);
          _notify(userId, AttendanceCaptureOutcome.incomplete, draft.type);
        case CaptureRecoveryQueue(
            :final draft,
            :final imagePath,
            :final recordedAt
          ):
          await _queueRecovered(
              userId, queue, db, draft, imagePath, recordedAt);
      }
    } finally {
      // The picker's copy is never needed again — a queued photo has been
      // copied to durable storage — and a discarded one must not leave an
      // employee's face sitting in the cache directory.
      if (photo != null) deleteSelfieQuietly(photo.path);
    }
  }

  /// The photo the picker cached for a killed process, or null. Android-only;
  /// an empty result, an error result, or a throwing channel all mean "no
  /// photo" — the draft then yields a retry message instead.
  Future<RecoveredPhoto?> _recoveredPhoto() async {
    if (!_isAndroid) return null;
    final String path;
    try {
      // Bounded: a hung platform channel here must not wedge recoverOnce()'s
      // cached future forever — every future caller awaits that same future.
      final response =
          await _retrieveLostData().timeout(_retrieveLostDataTimeout);
      if (response.isEmpty || response.exception != null) return null;
      final files = response.files;
      final found = (files != null && files.isNotEmpty)
          ? files.first.path
          : response.file?.path;
      if (found == null) return null;
      path = found;
    } catch (e, stack) {
      logUnexpected('retrieveLostData failed', e, stack);
      return null;
    }

    DateTime takenAt;
    try {
      takenAt = await _photoTakenAt(path);
    } catch (e, stack) {
      // Unreadable file time: now is the closest safe stand-in. It errs late
      // by the cold start, never early.
      logUnexpected('Could not read recovered photo time', e, stack);
      takenAt = _now();
    }
    return (path: path, takenAt: takenAt);
  }

  Future<void> _queueRecovered(
    int userId,
    AttendanceQueueController queue,
    AttendanceLocalDb db,
    AttendanceCaptureDraft draft,
    String imagePath,
    DateTime recordedAt,
  ) async {
    try {
      final storedPath = await _persistSelfie(File(imagePath));
      await queue.addOwningSelfie(
        PendingAttendanceRecord(
          type: draft.type,
          latitude: draft.latitude,
          longitude: draft.longitude,
          selfiePath: storedPath,
          recordedAt: recordedAt,
          operationId: draft.operationId,
        ),
      );
    } catch (e, stack) {
      logUnexpected('Could not queue recovered attendance capture', e, stack);
      await _clearDraftQuietly(db, draft);
      _notify(userId, AttendanceCaptureOutcome.incomplete, draft.type);
      return;
    }
    await _clearDraftQuietly(db, draft);
    _notify(userId, AttendanceCaptureOutcome.recovered, draft.type);
    // syncPending() syncs whoever is CURRENTLY signed in — if the account
    // changed mid-recovery, triggering it here would sync the new user's
    // queue instead of the one just recovered. Leave it pending; it syncs on
    // this user's next natural trigger (sign-in, startup, connectivity).
    if (_isSignedIn(userId)) {
      unawaited(_ref.read(attendanceSyncServiceProvider).syncPending());
    }
  }

  bool _isSignedIn(int userId) => _ref.read(currentUserProvider)?.id == userId;

  /// Only for the user the recovery ran for — never whoever signed in since.
  void _notify(
      int userId, AttendanceCaptureOutcome outcome, AttendanceType type) {
    if (!_isSignedIn(userId)) return;
    _ref.read(attendanceCaptureNoticeProvider.notifier).state =
        AttendanceCaptureNotice(outcome, type);
  }
}

final attendanceCaptureRecoveryProvider =
    Provider<AttendanceCaptureRecovery>((ref) {
  return AttendanceCaptureRecovery(ref);
});
