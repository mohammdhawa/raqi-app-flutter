import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/api_failure.dart';
import '../../../core/network/api_client.dart';
import '../domain/attendance_record.dart';
import '../domain/pending_attendance_record.dart';

/// One failed entry from a bulk sync — `index` refers to its position in
/// the request's `records[]`/`selfies[]` arrays, so callers can map it
/// back to the local queue entry that produced it.
class AttendanceSyncFailure {
  const AttendanceSyncFailure({required this.index, required this.error});

  final int index;
  final String error;

  factory AttendanceSyncFailure.fromJson(Map<String, dynamic> json) =>
      AttendanceSyncFailure(
        index: (json['index'] as num).toInt(),
        error: (json['error'] as String?) ?? 'تعذرت مزامنة هذا السجل.',
      );
}

/// Result of `POST /attendance/sync` — each entry is processed
/// independently, so a batch can partially succeed.
class AttendanceSyncResult {
  const AttendanceSyncResult({required this.succeeded, required this.failed});

  final List<AttendanceRecord> succeeded;
  final List<AttendanceSyncFailure> failed;

  factory AttendanceSyncResult.fromJson(Map<String, dynamic> json) =>
      AttendanceSyncResult(
        succeeded: ((json['succeeded'] as List?) ?? [])
            .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
        failed: ((json['failed'] as List?) ?? [])
            .map((e) => AttendanceSyncFailure.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Wraps the non-admin attendance endpoints (`/api/attendance/*`).
/// Returns parsed domain objects; throws [ApiFailure] on errors
/// (mapped by the [ApiClient] interceptor).
class AttendanceRepository {
  AttendanceRepository(this._api);

  final ApiClient _api;

  // Dio rejects with DioException(error: ApiFailure); unwrap so callers can
  // use `on ApiFailure catch` directly.
  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      if (e.error is ApiFailure) throw e.error as ApiFailure;
      rethrow;
    }
  }

  /// `POST /attendance/record` — multipart, single check-in/out.
  Future<AttendanceRecord> record({
    required AttendanceType type,
    required double latitude,
    required double longitude,
    required File selfie,
    required DateTime recordedAt,
  }) async {
    final form = FormData.fromMap({
      'type': type.apiValue,
      'latitude': latitude,
      'longitude': longitude,
      'recorded_at': recordedAt.toIso8601String(),
      'selfie': await MultipartFile.fromFile(
        selfie.path,
        filename: selfie.path.split(Platform.pathSeparator).last,
      ),
    });

    final response = await _run(() => _api.dio.post<Map<String, dynamic>>(
      '/attendance/record',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    ));
    return AttendanceRecord.fromJson(
      response.data!['record'] as Map<String, dynamic>,
    );
  }

  /// `POST /attendance/sync` — bulk upload of queued offline records.
  /// `records[]` and `selfies[]` are index-aligned, per the docs.
  Future<AttendanceSyncResult> sync(List<PendingAttendanceRecord> entries) async {
    final form = FormData();
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      form.fields.addAll([
        MapEntry('records[$i][type]', entry.type.apiValue),
        MapEntry('records[$i][latitude]', entry.latitude.toString()),
        MapEntry('records[$i][longitude]', entry.longitude.toString()),
        MapEntry(
          'records[$i][recorded_at]',
          entry.recordedAt.toIso8601String(),
        ),
      ]);
      form.files.add(MapEntry(
        'selfies[$i]',
        await MultipartFile.fromFile(
          entry.selfiePath,
          filename: entry.selfiePath.split(Platform.pathSeparator).last,
        ),
      ));
    }

    final response = await _run(() => _api.dio.post<Map<String, dynamic>>(
      '/attendance/sync',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    ));
    return AttendanceSyncResult.fromJson(response.data!);
  }

  /// `GET /attendance/my-records?date=&from=&to=&page=`
  Future<AttendanceRecordsPage> myRecords({
    DateTime? date,
    DateTime? from,
    DateTime? to,
    int page = 1,
  }) async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
      '/attendance/my-records',
      queryParameters: {
        'page': page,
        if (date != null) 'date': _formatDate(date),
        if (from != null) 'from': _formatDate(from),
        if (to != null) 'to': _formatDate(to),
      },
    ));
    return AttendanceRecordsPage.fromJson(response.data!);
  }

  String _formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
}

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(ref.watch(apiClientProvider));
});
