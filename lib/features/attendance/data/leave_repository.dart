import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/api_failure.dart';
import '../../../core/network/api_client.dart';
import '../domain/leave.dart';

/// One page of a leave listing, plus whether the paginator reports more
/// pages after it.
typedef LeaveRequestsPage = ({List<LeaveRequest> requests, bool hasMore});

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

  /// `GET /attendance/leave-types?for=…` — the HR-managed vocabulary that
  /// feeds the type picker.
  ///
  /// [form] is always sent: the unfiltered list contains types an employee may
  /// not request (an official mission is recorded by HR), and naming one of
  /// those on a request comes back as a 422 on `leave_type`.
  ///
  /// The backend returns them in creation order, which IS the display order —
  /// there is no `sort_order` field — so the list is passed through untouched.
  Future<List<LeaveType>> leaveTypes({
    LeaveTypeForm form = LeaveTypeForm.requests,
  }) async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
          '/attendance/leave-types',
          queryParameters: {'for': form.apiValue},
        ));
    return _extractList(response.data)
        .map(LeaveType.fromJson)
        .where((t) => t.id != 0)
        .toList();
  }

  /// `GET /attendance/leave-managers`
  ///
  /// Asks for [maxPerPage] explicitly. This endpoint is paginated and defaults
  /// to 25 a page (`HandlesListControls::perPage`), ordered `name asc` — and
  /// the picker it feeds has no search box and no load-more, so whatever is
  /// not on the first page simply does not exist as far as the form is
  /// concerned. With 25 managers and the single chief the roster ran to 26
  /// people and the chief sorted last, which put the one approver who
  /// habitually closes the chain on page two and out of reach entirely.
  ///
  /// 100 is the endpoint's own ceiling, not a safe upper bound on the company:
  /// past that, the real answer is the `search` parameter this endpoint
  /// already accepts, not a bigger page.
  Future<List<LeaveManager>> managers() async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
          '/attendance/leave-managers',
          queryParameters: {'per_page': maxPerPage},
        ));
    return _extractList(response.data)
        .map(LeaveManager.fromJson)
        .where((m) => m.id != 0)
        .toList();
  }

  /// `POST /attendance/leave-requests`
  ///
  /// The type is named by [leaveTypeId] only. The legacy free-text
  /// `leave_type` is deliberately never sent: the backend resolves such text
  /// against a type's code and names, so a near-miss like `"مرضية"` (the
  /// seeded name is `إجازة مرضية`) matches nothing, is stored verbatim and
  /// **deducts balance** — charging the employee for a sick day.
  ///
  /// [leaveTypeId] is `required` even though the endpoint accepts a request
  /// without one. An untyped request is filed as deducting AND skips the
  /// type's required-reason rule, so "no type" is not a neutral default —
  /// it is the wrong answer for every non-deducting type. Making it
  /// unskippable here means no future caller can reintroduce that silently;
  /// a form that cannot offer a type must refuse to submit instead.
  Future<LeaveRequest> create({
    required DateTime startDate,
    required DateTime endDate,
    required List<int> approverIds,
    required int leaveTypeId,
    String? reason,
  }) async {
    final response = await _run(() => _api.dio.post<Map<String, dynamic>>(
          '/attendance/leave-requests',
          data: {
            'start_date': _formatDate(startDate),
            'end_date': _formatDate(endDate),
            // Array order is the decision order. Do not also send the legacy
            // `manager_id`: this client owns the ordered contract now, and one
            // source of truth avoids a first-step mismatch validation error.
            'approver_ids': approverIds,
            'leave_type_id': leaveTypeId,
            if (reason != null && reason.isNotEmpty) 'reason': reason,
          },
        ));
    return _extractOne(response.data);
  }

  /// `GET /attendance/leave-requests` — the authenticated user's requests.
  Future<List<LeaveRequest>> myRequests({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
    int? perPage,
  }) async =>
      (await myRequestsPage(status: status, year: year, perPage: perPage))
          .requests;

  /// One page of [myRequests], with the paginator's own answer to "is there
  /// another page?" — so a caller scanning for a specific row knows when it
  /// has actually run out rather than guessing from the row count.
  Future<LeaveRequestsPage> myRequestsPage({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
    int? perPage,
    int page = 1,
  }) async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
          '/attendance/leave-requests',
          queryParameters: {
            if (status.apiValue != null) 'status': status.apiValue,
            if (year != null) 'year': year,
            if (perPage != null) 'per_page': perPage,
            if (page > 1) 'page': page,
          },
        ));
    return _extractPage(response.data);
  }

  /// `GET /attendance/leave-requests/approvals` — requests where the caller is
  /// any approver in the chain, including rows whose turn has not arrived.
  Future<List<LeaveRequest>> approvals({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? perPage,
  }) async =>
      (await approvalsPage(status: status, perPage: perPage)).requests;

  /// One page of [approvals] — see [myRequestsPage].
  Future<LeaveRequestsPage> approvalsPage({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? perPage,
    int page = 1,
  }) async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
          '/attendance/leave-requests/approvals',
          queryParameters: {
            if (status.apiValue != null) 'status': status.apiValue,
            if (perPage != null) 'per_page': perPage,
            if (page > 1) 'page': page,
          },
        ));
    return _extractPage(response.data);
  }

  /// The largest page the listing endpoints accept (`per_page` ≤ 100).
  static const int maxPerPage = 100;

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
          node['leave_types'] ??
          node['managers'] ??
          node['data'] ??
          node['items'] ??
          node;
      // Unwrap a paginator: { data: [...] }.
      if (node is Map && node['data'] is List) node = node['data'];
    }
    if (node is List) {
      return node
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  /// Parses one page: its rows, and whether the paginator reports more.
  ///
  /// "Fewer rows than we asked for" is deliberately NOT the end-of-list test
  /// — the server decides the page size, so a `per_page` it clamps would end
  /// a scan early and report a row that exists as missing. When the response
  /// carries no paginator at all (a bare list), there is exactly one page.
  LeaveRequestsPage _extractPage(dynamic data) => (
        requests: _extractList(data).map(LeaveRequest.fromJson).toList(),
        hasMore: _hasMorePages(data),
      );

  bool _hasMorePages(dynamic data) {
    final paginator = _paginator(data);
    if (paginator == null) return false;
    final current = _asInt(paginator['current_page']);
    final last = _asInt(paginator['last_page']);
    if (current != null && last != null) return current < last;
    // Older/leaner envelopes: the next-page link is the same statement.
    final next = paginator['next_page_url'];
    return next != null && next.toString().isNotEmpty;
  }

  /// The Laravel paginator inside the response envelope, or null when the
  /// payload is a bare list.
  Map? _paginator(dynamic data) {
    if (data is! Map) return null;
    for (final key in const ['leave_requests', 'leaveRequests', 'data']) {
      final node = data[key];
      if (node is Map && node['data'] is List) return node;
    }
    if (data['data'] is List && data.containsKey('current_page')) return data;
    return null;
  }

  int? _asInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  /// Pulls a single request map out of a create/review response and parses it.
  LeaveRequest _extractOne(dynamic data) {
    dynamic node = data;
    if (node is Map) {
      node =
          node['leave_request'] ?? node['leaveRequest'] ?? node['data'] ?? node;
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
