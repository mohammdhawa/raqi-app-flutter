import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/api_failure.dart';
import '../../../core/network/api_client.dart';
import '../domain/leave.dart';

/// Wraps the attendance Leave Management endpoints
/// (`/api/attendance/leave-*`). Returns parsed domain objects; throws
/// [ApiFailure] on errors (mapped by the [ApiClient] interceptor).
class LeaveRepository {
  LeaveRepository(this._api);

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

  /// `GET /attendance/leave-balance`
  Future<LeaveBalance> balance() async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
      '/attendance/leave-balance',
    ));
    final data = response.data ?? const {};
    final balance = data['balance'];
    return LeaveBalance.fromJson(
      balance is Map<String, dynamic> ? balance : data,
    );
  }

  /// `GET /attendance/leave-managers`
  Future<List<LeaveManager>> managers() async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
      '/attendance/leave-managers',
    ));
    return _extractList(response.data)
        .map(LeaveManager.fromJson)
        .where((m) => m.id != 0)
        .toList();
  }

  /// `POST /attendance/leave-requests`
  Future<LeaveRequest> create({
    required DateTime startDate,
    required DateTime endDate,
    required int managerId,
    String? leaveType,
    String? reason,
  }) async {
    final response = await _run(() => _api.dio.post<Map<String, dynamic>>(
      '/attendance/leave-requests',
      data: {
        'start_date': _formatDate(startDate),
        'end_date': _formatDate(endDate),
        'manager_id': managerId,
        if (leaveType != null && leaveType.isNotEmpty) 'leave_type': leaveType,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    ));
    return _extractOne(response.data);
  }

  /// `GET /attendance/leave-requests` — the authenticated user's requests.
  Future<List<LeaveRequest>> myRequests({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
  }) async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
      '/attendance/leave-requests',
      queryParameters: {
        if (status.apiValue != null) 'status': status.apiValue,
        if (year != null) 'year': year,
      },
    ));
    return _extractList(response.data).map(LeaveRequest.fromJson).toList();
  }

  /// `GET /attendance/leave-requests/approvals` — requests assigned to the
  /// authenticated manager for approval.
  Future<List<LeaveRequest>> approvals({
    LeaveStatusFilter status = LeaveStatusFilter.all,
  }) async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
      '/attendance/leave-requests/approvals',
      queryParameters: {
        if (status.apiValue != null) 'status': status.apiValue,
      },
    ));
    return _extractList(response.data).map(LeaveRequest.fromJson).toList();
  }

  /// `PATCH /attendance/leave-requests/{id}/review` with `{ "status": ... }`.
  Future<LeaveRequest> review({
    required int id,
    required LeaveStatus status,
  }) async {
    final response = await _run(() => _api.dio.patch<Map<String, dynamic>>(
      '/attendance/leave-requests/$id/review',
      data: {'status': status.apiValue},
    ));
    return _extractOne(response.data);
  }

  String _formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  /// Pulls a list of request maps out of whatever envelope the backend uses:
  /// a bare list, `{ data: [...] }`, a named key, or a Laravel paginator
  /// (`{ key: { data: [...] } }`).
  List<Map<String, dynamic>> _extractList(dynamic data) {
    dynamic node = data;
    if (node is Map) {
      node = node['leave_requests'] ??
          node['leaveRequests'] ??
          node['managers'] ??
          node['data'] ??
          node['items'] ??
          node;
      // Unwrap a paginator: { data: [...] }.
      if (node is Map && node['data'] is List) node = node['data'];
    }
    if (node is List) {
      return node.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
  }

  /// Pulls a single request map out of a create/review response and parses it.
  LeaveRequest _extractOne(dynamic data) {
    dynamic node = data;
    if (node is Map) {
      node = node['leave_request'] ??
          node['leaveRequest'] ??
          node['data'] ??
          node;
    }
    if (node is Map) {
      return LeaveRequest.fromJson(node.cast<String, dynamic>());
    }
    throw ApiFailure(
      code: ApiErrorCode.unknown,
      message: arabicMessageFor(ApiErrorCode.unknown),
    );
  }
}

final leaveRepositoryProvider = Provider<LeaveRepository>((ref) {
  return LeaveRepository(ref.watch(apiClientProvider));
});
