import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/attendance_repository.dart';
import '../../data/selfie_storage.dart';
import '../../domain/attendance_record.dart';
import '../../domain/attendance_window.dart';
import '../../domain/pending_attendance_record.dart';
import '../../domain/today_attendance_item.dart';
import 'attendance_queue_controller.dart';
import 'attendance_sync_service.dart';

class AttendanceControllerState {
  const AttendanceControllerState({
    this.isBootstrapping = true,
    this.isCapturing = false,
    this.remoteTodayRecords = const [],
    this.captureError,
  });

  /// Whether we're still fetching the user's last known record from the
  /// server (used to seed status on a fresh install / new device).
  final bool isBootstrapping;

  /// Whether a check-in/out capture (location + selfie) is in progress.
  final bool isCapturing;

  /// Today's records the server already knows about, from any device —
  /// combined with the local queue's entries to drive
  /// [attendanceStatusProvider] and [todayAttendanceProvider].
  final List<AttendanceRecord> remoteTodayRecords;

  /// Human-readable failure from the most recent capture attempt
  /// (permission denied, no GPS, camera cancelled, …).
  final String? captureError;

  AttendanceControllerState copyWith({
    bool? isBootstrapping,
    bool? isCapturing,
    List<AttendanceRecord>? remoteTodayRecords,
    String? captureError,
    bool clearCaptureError = false,
  }) =>
      AttendanceControllerState(
        isBootstrapping: isBootstrapping ?? this.isBootstrapping,
        isCapturing: isCapturing ?? this.isCapturing,
        remoteTodayRecords: remoteTodayRecords ?? this.remoteTodayRecords,
        captureError:
            clearCaptureError ? null : (captureError ?? this.captureError),
      );
}

/// Drives the check-in/out screen: seeds the user's last known status from
/// the server, then runs the capture flow (GPS → front-camera selfie →
/// local queue → background sync) whenever the user taps the action button.
class AttendanceController extends StateNotifier<AttendanceControllerState> {
  AttendanceController(this._repo, this._queue, this._syncService)
      : super(const AttendanceControllerState()) {
    _bootstrap();
  }

  final AttendanceRepository _repo;
  final AttendanceQueueController _queue;
  final AttendanceSyncService _syncService;

  /// Local calendar day of the last successful fetch, so [refreshToday] can
  /// skip redundant refetches on resumes within the same day.
  DateTime? _lastLoadedDay;

  /// Guards against overlapping fetches — two rapid resumes could otherwise
  /// race, and the response that arrives last (not the one sent last) would
  /// win, briefly reverting [AttendanceControllerState.remoteTodayRecords].
  bool _isLoading = false;

  Future<void> _bootstrap() async {
    if (_isLoading) return;
    _isLoading = true;
    try {
      final page = await _repo.myRecords(page: 1);
      if (!mounted) return;
      _lastLoadedDay = _dayOf(DateTime.now());
      state = state.copyWith(
        isBootstrapping: false,
        remoteTodayRecords:
            page.records.where((r) => _isToday(r.recordedAt)).toList(),
      );
    } on Exception {
      // Offline on first launch — fine, the local queue (if any) still
      // drives the status; an empty queue just defaults to "checked out".
      if (!mounted) return;
      state = state.copyWith(isBootstrapping: false);
    } finally {
      _isLoading = false;
    }
  }

  /// Re-fetches today's records from the server on app resume so a night spent
  /// in the background doesn't leave yesterday's records driving this morning's
  /// status. Resume fires on every task switch, so this refetches only when the
  /// calendar day has actually changed since the last successful load.
  Future<void> refreshToday() {
    if (_lastLoadedDay != null && _lastLoadedDay == _dayOf(DateTime.now())) {
      return Future.value();
    }
    return _bootstrap();
  }

  /// Runs the full capture flow for [type] (the action the user tapped —
  /// "تسجيل حضور" or "تسجيل انصراف"): GPS fix, front-camera selfie, then
  /// persists to the local queue immediately so it survives app kills,
  /// and kicks off a background sync attempt.
  ///
  /// Returns true once the record is safely queued locally — the caller
  /// doesn't need to wait for the network round-trip.
  Future<bool> checkInOrOut(AttendanceType type) async {
    if (state.isCapturing) return false;
    state = state.copyWith(isCapturing: true, clearCaptureError: true);

    try {
      final position = await _capturePosition();
      if (position == null) {
        state = state.copyWith(
          isCapturing: false,
          captureError:
              'تعذّر تحديد موقعك. تأكد من تفعيل خدمة الموقع ومنح إذن الوصول إليه.',
        );
        return false;
      }

      final selfiePath = await _captureSelfie();
      if (selfiePath == null) {
        state = state.copyWith(
          isCapturing: false,
          captureError: 'لم يتم التقاط صورة شخصية.',
        );
        return false;
      }

      try {
        await _queue.add(
          PendingAttendanceRecord(
            type: type,
            latitude: position.latitude,
            longitude: position.longitude,
            selfiePath: selfiePath,
            recordedAt: DateTime.now(),
          ),
        );
      } catch (_) {
        // The persisted selfie is only ever cleaned up through its queue
        // row — if the insert fails, delete the copy or it leaks forever.
        deleteSelfieQuietly(await resolveSelfiePath(selfiePath));
        rethrow;
      }

      if (!mounted) return true;
      state = state.copyWith(isCapturing: false);
      // Fire-and-forget — UI reflects progress via the queue's sync status,
      // not this future. Failure (e.g. offline) just leaves it queued.
      unawaited(_syncService.syncPending());
      return true;
    } catch (e) {
      // Catch Object, not just Exception: AttendanceQueueController.add throws
      // a StateError (an Error) when signed out, which would otherwise escape
      // and leave isCapturing stuck true, dead-locking the button.
      if (!mounted) return false;
      state = state.copyWith(
        isCapturing: false,
        captureError: 'حدث خطأ غير متوقع: $e',
      );
      return false;
    }
  }

  void clearCaptureError() => state = state.copyWith(clearCaptureError: true);

  Future<Position?> _capturePosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Captures a front-camera selfie and persists it out of the OS cache into
  /// durable app-support storage. Returns the stored path (relative to
  /// app-support), or null if the user cancelled the camera. A copy failure
  /// (e.g. disk full) throws and aborts the capture — never queue the fragile
  /// cache path, which is exactly what MIUI cleaners wipe.
  Future<String?> _captureSelfie() async {
    final shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 80,
    );
    if (shot == null) return null;
    return persistSelfieForUpload(File(shot.path));
  }
}

final attendanceControllerProvider =
    StateNotifierProvider<AttendanceController, AttendanceControllerState>(
        (ref) {
  return AttendanceController(
    ref.watch(attendanceRepositoryProvider),
    ref.watch(attendanceQueueProvider.notifier),
    ref.watch(attendanceSyncServiceProvider),
  );
});

/// The current local calendar day (midnight-truncated), recomputed shortly
/// after each midnight.
///
/// Day-scoped providers must watch this instead of calling `DateTime.now()`
/// directly: Riverpod only recomputes when a dependency changes, so an app
/// kept alive across midnight would otherwise keep serving yesterday's
/// status (e.g. still offering "تسجيل انصراف" the next morning).
final currentLocalDayProvider = Provider<DateTime>((ref) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  // Small buffer past midnight so a timer that fires marginally early
  // can't recompute to the same (old) day and never roll over.
  final untilNextDay = today.add(const Duration(days: 1)).difference(now) +
      const Duration(seconds: 1);
  final timer = Timer(untilNextDay, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return today;
});

/// The user's current status for this calendar day only.
///
/// Server-rejected local entries and backend-closed missing-checkout records
/// are not valid attendance state. Excluding them also lets the employee retry
/// the correct action after a deterministic sync rejection.
final attendanceStatusProvider = Provider<AttendanceType?>((ref) {
  return resolveAttendanceStatus(
    remoteRecords: ref.watch(attendanceControllerProvider).remoteTodayRecords,
    localRecords: ref.watch(attendanceQueueProvider),
    now: ref.watch(currentLocalDayProvider),
  );
});

/// Arabic reason the checkout button is pre-disabled because the backend's
/// minimum check-in→checkout gap hasn't elapsed yet, or `null` when checkout
/// is allowed (the gap has passed, or the user isn't currently checked in).
///
/// Mirrors `attendance.min_checkout_gap_minutes` (default 60) so an obviously
/// too-early checkout never even leaves the device; the backend stays
/// authoritative and still rejects one with a 422 message if it's configured
/// to a longer gap. autoDispose so the per-minute countdown timer is torn down
/// as soon as the screen stops watching this.
final checkOutBlockedReasonProvider = Provider.autoDispose<String?>((ref) {
  final latest = resolveLatestAttendance(
    remoteRecords: ref.watch(attendanceControllerProvider).remoteTodayRecords,
    localRecords: ref.watch(attendanceQueueProvider),
    now: ref.watch(currentLocalDayProvider),
  );
  if (latest == null || latest.type != AttendanceType.checkIn) return null;

  final now = DateTime.now();
  final remaining = checkoutGapRemaining(latest.recordedAt, now);
  if (remaining == null) return null;

  // Re-evaluate right after the displayed minute count next changes — i.e. at
  // the next whole-minute boundary of the remaining time, or exactly when the
  // gap lifts, whichever is sooner — so the countdown never lags by up to a
  // minute, while still rebuilding at most once per minute. (The small buffer
  // lands us just past the boundary, so the recomputed value is the new one.)
  final msIntoMinute =
      remaining.inMilliseconds % Duration.millisecondsPerMinute;
  final untilNextTick = Duration(
    milliseconds:
        (msIntoMinute == 0 ? Duration.millisecondsPerMinute : msIntoMinute) +
            250,
  );
  final timer = Timer(untilNextTick, ref.invalidateSelf);
  ref.onDispose(timer.cancel);

  return checkOutBlockedReason(latest.recordedAt, now);
});

/// Resolves the latest valid attendance action for [now]'s local calendar day.
/// Exposed separately from the provider so day-boundary behavior can be tested
/// without camera, location, database, or network dependencies.
AttendanceType? resolveAttendanceStatus({
  required Iterable<AttendanceRecord> remoteRecords,
  required Iterable<PendingAttendanceRecord> localRecords,
  DateTime? now,
}) =>
    resolveLatestAttendance(
      remoteRecords: remoteRecords,
      localRecords: localRecords,
      now: now,
    )?.type;

/// The latest valid attendance action governing [now]'s local calendar day —
/// both its type and the moment it was recorded — or `null` when there's no
/// valid record for today. [resolveAttendanceStatus] (which action to offer
/// next) and [checkOutBlockedReasonProvider] (how long since check-in) both
/// derive from this single selection, so they can never disagree about which
/// record is the latest one.
({AttendanceType type, DateTime recordedAt})? resolveLatestAttendance({
  required Iterable<AttendanceRecord> remoteRecords,
  required Iterable<PendingAttendanceRecord> localRecords,
  DateTime? now,
}) {
  final today = (now ?? DateTime.now()).toLocal();

  AttendanceRecord? latestRemote;
  for (final r in remoteRecords) {
    if (r.isMissingCheckout || !_isSameLocalDay(r.recordedAt, today)) continue;
    if (latestRemote == null || r.recordedAt.isAfter(latestRemote.recordedAt)) {
      latestRemote = r;
    }
  }

  PendingAttendanceRecord? latestLocal;
  for (final r in localRecords) {
    if (r.isFailed || !_isSameLocalDay(r.recordedAt, today)) continue;
    // Skip a local record the server already knows about: the remote copy is
    // authoritative and was already considered above — including being
    // excluded when the backend auto-closed it as missing_checkout. Without
    // this, a synced local check-in (the queue keeps synced rows) keeps
    // driving status even after the server closed the day, so the UI wrongly
    // keeps the user "checked in" and offers a checkout the server rejects.
    if (_hasRemoteTwin(r, remoteRecords)) continue;
    if (latestLocal == null || r.recordedAt.isAfter(latestLocal.recordedAt)) {
      latestLocal = r;
    }
  }

  if (latestLocal == null) {
    return latestRemote == null
        ? null
        : (type: latestRemote.type, recordedAt: latestRemote.recordedAt);
  }
  if (latestRemote == null) {
    return (type: latestLocal.type, recordedAt: latestLocal.recordedAt);
  }
  return latestLocal.recordedAt.isAfter(latestRemote.recordedAt)
      ? (type: latestLocal.type, recordedAt: latestLocal.recordedAt)
      : (type: latestRemote.type, recordedAt: latestRemote.recordedAt);
}

/// Whether [local] is the same logical check-in/out as a record the server
/// already returned — matched by type and near-identical time. Used both to
/// let the authoritative remote copy govern status and to avoid showing a
/// duplicate tile in "today's records".
bool _hasRemoteTwin(
  PendingAttendanceRecord local,
  Iterable<AttendanceRecord> remoteRecords,
) {
  return remoteRecords.any(
    (rt) =>
        rt.type == local.type &&
        rt.recordedAt.difference(local.recordedAt).abs() <
            const Duration(minutes: 2),
  );
}

DateTime _dayOf(DateTime d) {
  final local = d.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool _isToday(DateTime d) {
  return _isSameLocalDay(d, DateTime.now());
}

bool _isSameLocalDay(DateTime a, DateTime b) {
  final localA = a.toLocal();
  final localB = b.toLocal();
  return localA.year == localB.year &&
      localA.month == localB.month &&
      localA.day == localB.day;
}

/// "Today's records" (سجلات اليوم): the server's confirmed records for
/// today — from any device — plus this device's local-queue entries for
/// today, so a fresh check-in appears immediately instead of waiting for
/// the next bootstrap. A local entry already represented in
/// [AttendanceControllerState.remoteTodayRecords] (matched by type and
/// recorded time) isn't duplicated.
final todayAttendanceProvider = Provider<List<TodayAttendanceItem>>((ref) {
  final today = ref.watch(currentLocalDayProvider);
  // Re-filter both sources against the reactive day — remoteTodayRecords
  // was filtered at fetch time, so after midnight it holds yesterday's
  // records until the next bootstrap/refresh.
  final remoteToday = ref
      .watch(attendanceControllerProvider)
      .remoteTodayRecords
      .where((r) => _isSameLocalDay(r.recordedAt, today))
      .toList();
  final queue = ref.watch(attendanceQueueProvider);

  final localToday = queue
      .where((r) => _isSameLocalDay(r.recordedAt, today))
      .where((r) => !_hasRemoteTwin(r, remoteToday));

  final items = [
    ...remoteToday.map(TodayAttendanceItem.remote),
    ...localToday.map(TodayAttendanceItem.local),
  ];
  items.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
  return items;
});
