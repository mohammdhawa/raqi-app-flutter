import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/attendance_repository.dart';
import '../../domain/attendance_record.dart';
import '../../domain/pending_attendance_record.dart';
import '../../domain/today_attendance_item.dart';
import 'attendance_queue_controller.dart';
import 'attendance_sync_service.dart';

class AttendanceControllerState {
  const AttendanceControllerState({
    this.isBootstrapping = true,
    this.isCapturing = false,
    this.remoteLastRecord,
    this.remoteTodayRecords = const [],
    this.captureError,
  });

  /// Whether we're still fetching the user's last known record from the
  /// server (used to seed status on a fresh install / new device).
  final bool isBootstrapping;

  /// Whether a check-in/out capture (location + selfie) is in progress.
  final bool isCapturing;

  /// The most recent record the server knows about — combined with the
  /// local queue to derive [attendanceStatusProvider].
  final AttendanceRecord? remoteLastRecord;

  /// Today's records the server already knows about, from any device —
  /// combined with the local queue's entries to drive
  /// [todayAttendanceProvider].
  final List<AttendanceRecord> remoteTodayRecords;

  /// Human-readable failure from the most recent capture attempt
  /// (permission denied, no GPS, camera cancelled, …).
  final String? captureError;

  AttendanceControllerState copyWith({
    bool? isBootstrapping,
    bool? isCapturing,
    AttendanceRecord? remoteLastRecord,
    List<AttendanceRecord>? remoteTodayRecords,
    String? captureError,
    bool clearCaptureError = false,
  }) => AttendanceControllerState(
    isBootstrapping: isBootstrapping ?? this.isBootstrapping,
    isCapturing: isCapturing ?? this.isCapturing,
    remoteLastRecord: remoteLastRecord ?? this.remoteLastRecord,
    remoteTodayRecords: remoteTodayRecords ?? this.remoteTodayRecords,
    captureError: clearCaptureError ? null : (captureError ?? this.captureError),
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

  Future<void> _bootstrap() async {
    try {
      final page = await _repo.myRecords(page: 1);
      if (!mounted) return;
      state = state.copyWith(
        isBootstrapping: false,
        remoteLastRecord: page.records.isNotEmpty ? page.records.first : null,
        remoteTodayRecords: page.records.where((r) => _isToday(r.recordedAt)).toList(),
      );
    } on Exception {
      // Offline on first launch — fine, the local queue (if any) still
      // drives the status; an empty queue just defaults to "checked out".
      if (!mounted) return;
      state = state.copyWith(isBootstrapping: false);
    }
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

      final selfie = await _captureSelfie();
      if (selfie == null) {
        state = state.copyWith(
          isCapturing: false,
          captureError: 'لم يتم التقاط صورة شخصية.',
        );
        return false;
      }

      await _queue.add(
        PendingAttendanceRecord(
          type: type,
          latitude: position.latitude,
          longitude: position.longitude,
          selfiePath: selfie.path,
          recordedAt: DateTime.now(),
        ),
      );

      if (!mounted) return true;
      state = state.copyWith(isCapturing: false);
      // Fire-and-forget — UI reflects progress via the queue's sync status,
      // not this future. Failure (e.g. offline) just leaves it queued.
      unawaited(_syncService.syncPending());
      return true;
    } on Exception catch (e) {
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

  Future<File?> _captureSelfie() async {
    final shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 80,
    );
    if (shot == null) return null;
    return File(shot.path);
  }
}

final attendanceControllerProvider =
    StateNotifierProvider<AttendanceController, AttendanceControllerState>((ref) {
      return AttendanceController(
        ref.watch(attendanceRepositoryProvider),
        ref.watch(attendanceQueueProvider.notifier),
        ref.watch(attendanceSyncServiceProvider),
      );
    });

/// The user's current status — checked in or out — derived from whichever
/// record is more recent: the latest locally-queued one, or the latest one
/// the server knows about (seeded once on load; covers fresh installs and
/// actions taken from another device). Null means "no history at all".
final attendanceStatusProvider = Provider<AttendanceType?>((ref) {
  final queue = ref.watch(attendanceQueueProvider);
  final remote = ref.watch(attendanceControllerProvider).remoteLastRecord;

  PendingAttendanceRecord? latestLocal;
  for (final r in queue) {
    if (latestLocal == null || r.recordedAt.isAfter(latestLocal.recordedAt)) {
      latestLocal = r;
    }
  }

  if (latestLocal == null) return remote?.type;
  if (remote == null) return latestLocal.type;
  return latestLocal.recordedAt.isAfter(remote.recordedAt)
      ? latestLocal.type
      : remote.type;
});

bool _isToday(DateTime d) {
  final now = DateTime.now();
  return d.year == now.year && d.month == now.month && d.day == now.day;
}

/// "Today's records" (سجلات اليوم): the server's confirmed records for
/// today — from any device — plus this device's local-queue entries for
/// today, so a fresh check-in appears immediately instead of waiting for
/// the next bootstrap. A local entry already represented in
/// [AttendanceControllerState.remoteTodayRecords] (matched by type and
/// recorded time) isn't duplicated.
final todayAttendanceProvider = Provider<List<TodayAttendanceItem>>((ref) {
  final remoteToday = ref.watch(attendanceControllerProvider).remoteTodayRecords;
  final queue = ref.watch(attendanceQueueProvider);

  final localToday = queue.where((r) => _isToday(r.recordedAt)).where((r) {
    return !remoteToday.any(
      (rt) =>
          rt.type == r.type &&
          rt.recordedAt.difference(r.recordedAt).abs() < const Duration(minutes: 2),
    );
  });

  final items = [
    ...remoteToday.map(TodayAttendanceItem.remote),
    ...localToday.map(TodayAttendanceItem.local),
  ];
  items.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
  return items;
});
