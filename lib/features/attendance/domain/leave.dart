// Domain models for the attendance Leave Management module
// (`/api/attendance/leave-*`).
//
// Only users with role `manager` can submit leave requests; the selected
// approving manager approves or rejects them — no chief/executive step.
//
// Leave is charged in WORKING days only: the backend deducts Sunday–Thursday
// and ignores the weekend (Friday & Saturday). The `days` / `requested_days`
// the API returns are already that chargeable working-day count, and the
// client mirrors the same rule (see [workingDaysBetween]) for previews and
// pre-validation.

import 'attendance_window.dart' show isWorkingDay;

/// Lifecycle of a leave request, mirroring the `status` field returned by
/// the backend (`pending` / `approved` / `rejected`).
enum LeaveStatus {
  pending,
  approved,
  rejected;

  static LeaveStatus fromString(String? raw) {
    switch (raw) {
      case 'approved':
        return LeaveStatus.approved;
      case 'rejected':
        return LeaveStatus.rejected;
      default:
        return LeaveStatus.pending;
    }
  }

  String get apiValue => switch (this) {
    LeaveStatus.pending => 'pending',
    LeaveStatus.approved => 'approved',
    LeaveStatus.rejected => 'rejected',
  };

  String get arabicLabel => switch (this) {
    LeaveStatus.pending => 'قيد الانتظار',
    LeaveStatus.approved => 'معتمدة',
    LeaveStatus.rejected => 'مرفوضة',
  };
}

/// Filter used by the "my requests" / "approvals" lists. [all] sends no
/// `status` query parameter.
enum LeaveStatusFilter {
  all,
  pending,
  approved,
  rejected;

  /// The `status=` query value, or null for [all].
  String? get apiValue => switch (this) {
    LeaveStatusFilter.all => null,
    LeaveStatusFilter.pending => 'pending',
    LeaveStatusFilter.approved => 'approved',
    LeaveStatusFilter.rejected => 'rejected',
  };

  String get arabicLabel => switch (this) {
    LeaveStatusFilter.all => 'الكل',
    LeaveStatusFilter.pending => 'قيد الانتظار',
    LeaveStatusFilter.approved => 'معتمدة',
    LeaveStatusFilter.rejected => 'مرفوضة',
  };
}

/// The authenticated user's annual leave balance
/// (`GET /attendance/leave-balance` → `balance`).
class LeaveBalance {
  const LeaveBalance({
    required this.year,
    required this.allocatedDays,
    required this.usedDays,
    required this.remainingDays,
  });

  final int year;
  final int allocatedDays;
  final int usedDays;
  final int remainingDays;

  factory LeaveBalance.fromJson(Map<String, dynamic> json) => LeaveBalance(
    year: _toInt(json['year']) ?? DateTime.now().year,
    allocatedDays: _toInt(json['allocated_days']) ?? 0,
    usedDays: _toInt(json['used_days']) ?? 0,
    remainingDays: _toInt(json['remaining_days']) ?? 0,
  );
}

/// A manager who can be selected to approve a leave request
/// (`GET /attendance/leave-managers`). Kept deliberately tolerant of the
/// exact response shape — only id + name are required to drive the picker.
class LeaveManager {
  const LeaveManager({
    required this.id,
    required this.name,
    this.departmentName,
  });

  final int id;
  final String name;
  final String? departmentName;

  factory LeaveManager.fromJson(Map<String, dynamic> json) {
    final dept = json['department'];
    return LeaveManager(
      id: _toInt(json['id']) ?? 0,
      name: (json['name'] as String?) ?? '—',
      departmentName: dept is Map ? dept['name'] as String? : null,
    );
  }
}

/// A leave request, as returned by the list / create / review endpoints.
class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.leaveType,
    this.reason,
    this.managerId,
    this.managerName,
    this.requesterId,
    this.requesterName,
    this.createdAt,
    this.reviewedAt,
    int? days,
  }) : _days = days;

  final int id;
  final DateTime startDate;
  final DateTime endDate;
  final LeaveStatus status;
  final String? leaveType;
  final String? reason;

  /// The selected approving manager.
  final int? managerId;
  final String? managerName;

  /// The employee who submitted the request (useful on the approvals list).
  final int? requesterId;
  final String? requesterName;

  final DateTime? createdAt;
  final DateTime? reviewedAt;

  final int? _days;

  /// Chargeable working days (Sun–Thu) the request deducts from the balance.
  /// Prefers the server's count (`days` / `requested_days`); falls back to a
  /// locally computed working-day count when the backend doesn't send one.
  int get days => _days ?? workingDaysBetween(startDate, endDate);

  bool get isPending => status == LeaveStatus.pending;
  bool get isApproved => status == LeaveStatus.approved;

  /// Whether this approved request covers [day] (date-only comparison).
  bool coversDate(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    final manager = json['manager'];
    final user = json['user'];
    return LeaveRequest(
      id: _toInt(json['id']) ?? 0,
      startDate: _toDate(json['start_date']) ?? DateTime.now(),
      endDate: _toDate(json['end_date']) ?? DateTime.now(),
      status: LeaveStatus.fromString(json['status'] as String?),
      leaveType: json['leave_type'] as String?,
      reason: json['reason'] as String?,
      managerId: _toInt(json['manager_id']) ??
          (manager is Map ? _toInt(manager['id']) : null),
      managerName: manager is Map ? manager['name'] as String? : null,
      requesterId: _toInt(json['user_id']) ??
          (user is Map ? _toInt(user['id']) : null),
      requesterName: user is Map ? user['name'] as String? : null,
      createdAt: _toDate(json['created_at']),
      reviewedAt: _toDate(json['reviewed_at']),
      days: _toInt(json['days']) ??
          _toInt(json['days_count']) ??
          _toInt(json['requested_days']),
    );
  }
}

/// Inclusive day count between two dates (all calendar days).
int daysBetween(DateTime start, DateTime end) {
  final a = DateTime(start.year, start.month, start.day);
  final b = DateTime(end.year, end.month, end.day);
  return b.difference(a).inDays.abs() + 1;
}

/// Inclusive count of WORKING days (Sun–Thu) between [start] and [end] — the
/// chargeable leave duration, excluding Fridays & Saturdays. Mirrors the
/// backend's deduction rule so the form can preview the deducted days and
/// block a request that contains no working day. Returns 0 if [end] is before
/// [start].
int workingDaysBetween(DateTime start, DateTime end) {
  var a = DateTime(start.year, start.month, start.day);
  final b = DateTime(end.year, end.month, end.day);
  if (b.isBefore(a)) return 0;
  var count = 0;
  while (!a.isAfter(b)) {
    if (isWorkingDay(a)) count++;
    a = a.add(const Duration(days: 1));
  }
  return count;
}

int? _toInt(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString());
}

DateTime? _toDate(dynamic raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toLocal();
}
