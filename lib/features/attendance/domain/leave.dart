// Domain models for the attendance Leave Management module
// (`/api/attendance/leave-*`).
//
// A submitted request carries an ordered chain of managers / chiefs. Exactly
// one step is current at a time; an approval advances the chain, while a
// rejection ends the request and marks every later step skipped. The server is
// authoritative for whose turn it is — the client only mirrors that state.
//
// Leave is charged in WORKING days, which the server's calendar currently
// defines as every day of the week — no day is skipped inside a span. The
// `days` / `requested_days` the API returns are already that count, and the
// client mirrors the same rule (see [workingDaysBetween]) for previews and
// pre-validation only — the server stays authoritative, and the calendar it
// applies is configuration that has changed before.
//
// Whether those days cost the employee anything is a separate question,
// answered by the type's `deducts_balance` flag (see [LeaveType]); it is
// snapshotted onto the request when filed and must never be inferred from the
// type's name.

import '../../../core/errors/api_failure.dart';
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

/// Lifecycle of one approver's step in an ordered leave workflow.
///
/// This deliberately is not [LeaveStatus]. A request can only be pending,
/// approved or rejected; `skipped` belongs to a later step that will never be
/// asked because an earlier approver rejected the request. Keeping the enums
/// separate prevents a step-only value from being assigned to the request.
enum LeaveApprovalStatus {
  pending,
  approved,
  rejected,
  skipped;

  static LeaveApprovalStatus fromString(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'approved':
        return LeaveApprovalStatus.approved;
      case 'rejected':
        return LeaveApprovalStatus.rejected;
      case 'skipped':
        return LeaveApprovalStatus.skipped;
      default:
        return LeaveApprovalStatus.pending;
    }
  }

  String get apiValue => switch (this) {
        LeaveApprovalStatus.pending => 'pending',
        LeaveApprovalStatus.approved => 'approved',
        LeaveApprovalStatus.rejected => 'rejected',
        LeaveApprovalStatus.skipped => 'skipped',
      };

  String get arabicLabel => switch (this) {
        LeaveApprovalStatus.pending => 'قيد الانتظار',
        LeaveApprovalStatus.approved => 'تمت الموافقة',
        LeaveApprovalStatus.rejected => 'مرفوضة',
        LeaveApprovalStatus.skipped => 'تم تجاوزها',
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

/// Which form a leave type may be offered on. The employee app only ever
/// files its own requests, so it always asks for [requests]: the unfiltered
/// vocabulary includes types HR records on the employee's behalf (an official
/// mission), and naming one of those on a request is a 422.
enum LeaveTypeForm {
  requests,
  excuses;

  /// The `for=` query value.
  String get apiValue => name;
}

/// One entry of the HR-managed leave vocabulary
/// (`GET /attendance/leave-types?for=requests` → `leave_types`).
///
/// The reason this is a table on the backend and a model here is
/// [deductsBalance]: it is the only thing that decides whether taking the
/// leave costs the employee a day of their allocation, and it is snapshotted
/// onto the request when it is filed. Never infer it from [nameAr] or [code] —
/// an admin can add a type at any time, and the two eras of stored
/// `leave_type` strings (raw code vs. Arabic label) make the name ambiguous.
class LeaveType {
  const LeaveType({
    required this.id,
    required this.code,
    required this.nameAr,
    required this.deductsBalance,
    this.nameEn,
    this.requiresReason = false,
  });

  final int id;

  /// Stable identifier (`annual`, `sick`, …) — key any local logic on this,
  /// never on the label.
  final String code;

  /// The picker label, already Arabic.
  final String nameAr;
  final String? nameEn;

  /// Whether taking this leave consumes the annual balance. `true` for
  /// `annual` / `emergency`; `false` for `sick` / `bereavement` / `unpaid`,
  /// which justify the absence for free.
  final bool deductsBalance;

  /// When true the backend returns 422 on `reason` unless one is given.
  final bool requiresReason;

  /// What to show in the picker — [nameAr] normally, degrading through the
  /// English name to the raw code so a half-filled row is never blank.
  String get label => nameAr.isNotEmpty ? nameAr : (nameEn ?? code);

  factory LeaveType.fromJson(Map<String, dynamic> json) => LeaveType(
        id: _toInt(json['id']) ?? 0,
        code: (json['code'] as String?) ?? '',
        nameAr: (json['name_ar'] as String?) ?? '',
        nameEn: json['name_en'] as String?,
        deductsBalance: _toBool(json['deducts_balance']) ?? true,
        requiresReason: _toBool(json['requires_reason']) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name_ar': nameAr,
        'name_en': nameEn,
        'deducts_balance': deductsBalance,
        'requires_reason': requiresReason,
      };
}

/// The authenticated user's annual leave balance
/// (`GET /attendance/leave-balance` → `balance`).
///
/// No arithmetic relates these four figures: [nonDeductingDays] is
/// deliberately **outside** [usedDays], and [remainingDays] is unaffected by
/// it, so `allocated == used + nonDeducting + remaining` does not hold and is
/// not meant to. Take every figure from the latest response rather than
/// recomputing one from the others.
class LeaveBalance {
  const LeaveBalance({
    required this.year,
    required this.allocatedDays,
    required this.usedDays,
    required this.remainingDays,
    this.nonDeductingDays = 0,
    this.overBalanceDays = 0,
  });

  final int year;
  final int allocatedDays;

  /// Approved days charged against the allocation — deducting types only.
  final int usedDays;
  final int remainingDays;

  /// Approved days taken under a type that does NOT consume the allocation
  /// (sick, bereavement, unpaid…), whoever filed them.
  ///
  /// Not the attendance reports' `excused_days`, which counts HR-filed
  /// excuses whether or not they deduct. Different sets — never map one onto
  /// the other and never sum them. Defaults to 0 so a backend predating the
  /// field behaves exactly as before.
  final int nonDeductingDays;

  /// Days approved past the allocation — non-zero only when HR force-recorded
  /// an excuse beyond it. [remainingDays] stays clamped at 0 in that case.
  final int overBalanceDays;

  factory LeaveBalance.fromJson(Map<String, dynamic> json) => LeaveBalance(
        year: _toInt(json['year']) ?? DateTime.now().year,
        allocatedDays: _toInt(json['allocated_days']) ?? 0,
        usedDays: _toInt(json['used_days']) ?? 0,
        remainingDays: _toInt(json['remaining_days']) ?? 0,
        nonDeductingDays: _toInt(json['non_deducting_days']) ?? 0,
        overBalanceDays: _toInt(json['over_balance_days']) ?? 0,
      );
}

/// Stands in for a name the payload did not carry. Kept as one constant
/// because both [LeaveManager] and [LeaveApprovalStep] produce it and the UI
/// has to recognise it: comparing against a literal em dash in each screen
/// makes changing the glyph a silent behaviour change somewhere else. Each of
/// those classes exposes a `hasName` for exactly that question.
const String _unnamed = '—';

/// A manager or chief who can be selected to approve a leave request
/// (`GET /attendance/leave-managers`). Kept deliberately tolerant of the exact
/// response shape — only id + name are required to drive the picker.
class LeaveManager {
  const LeaveManager({
    required this.id,
    required this.name,
    this.departmentName,
    this.sectionName,
  });

  final int id;
  final String name;
  final String? departmentName;

  /// The approver's section, when the payload nested one. Shown under the name
  /// in the picker: a company-wide roster puts several same-named managers in
  /// one list, and the department alone does not always separate them.
  final String? sectionName;

  /// False when the payload carried no usable name and [name] is only the
  /// neutral placeholder. Mirrors [LeaveApprovalStep.hasName]: a picker asks
  /// this instead of rendering the placeholder as if it were somebody's name,
  /// or building an avatar initial out of the glyph.
  bool get hasName => name != _unnamed;

  factory LeaveManager.fromJson(Map<String, dynamic> json) {
    final dept = json['department'];
    final section = json['section'];
    return LeaveManager(
      id: _toInt(json['id']) ?? 0,
      name: (json['name'] as String?) ?? _unnamed,
      departmentName: dept is Map ? dept['name'] as String? : null,
      sectionName: section is Map ? section['name'] as String? : null,
    );
  }
}

/// One decision in a leave request's sequential approval chain.
///
/// The API normally includes both `user_id` and the nested `user`, but list
/// projections and older cached payloads may omit either. Parsing therefore
/// degrades to the nested id / a neutral name instead of discarding the whole
/// request — the order and status still explain the workflow usefully.
class LeaveApprovalStep {
  const LeaveApprovalStep({
    required this.userId,
    required this.userName,
    required this.approvalOrder,
    required this.status,
    this.reviewedAt,
  });

  final int userId;
  final String userName;
  final int approvalOrder;
  final LeaveApprovalStatus status;
  final DateTime? reviewedAt;

  /// False when the payload carried no usable name and [userName] is only the
  /// neutral placeholder — so callers can ask about the name instead of
  /// string-comparing the glyph this class chose to stand in for it.
  bool get hasName => userName != _unnamed;

  /// True while this step is the one still waiting on its approver. Approved,
  /// rejected and skipped steps are all finished: nothing further will ever be
  /// asked of the person named on them.
  bool get isPending => status == LeaveApprovalStatus.pending;

  factory LeaveApprovalStep.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    final nestedUser = user is Map ? user : null;
    final nestedName = nestedUser?['name'];
    final directName = json['user_name'];
    return LeaveApprovalStep(
      userId: _toInt(json['user_id']) ??
          (nestedUser == null ? null : _toInt(nestedUser['id'])) ??
          0,
      userName: directName is String && directName.isNotEmpty
          ? directName
          : nestedName is String && nestedName.isNotEmpty
              ? nestedName
              : _unnamed,
      approvalOrder: _toInt(json['approval_order']) ?? 0,
      status: LeaveApprovalStatus.fromString(json['status']?.toString()),
      reviewedAt: _toDate(json['reviewed_at']),
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
    this.leaveTypeId,
    this.deductsBalance = true,
    this.isExcuse = false,
    this.createdBy,
    this.reason,
    this.managerId,
    this.managerName,
    this.approvals = const [],
    this.currentApproverId,
    this.canReview,
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

  /// The type's label as stored on the row. Ambiguous across two eras —
  /// newly filed rows hold the Arabic label, older ones the raw free text
  /// (`annual`, `sick`) — so display it, but never switch on it. Use
  /// [leaveTypeId] / the cached type's `code` / [deductsBalance] for logic.
  final String? leaveType;

  /// Links the row to the HR vocabulary. `null` on rows filed before types
  /// existed, and on free text that matched no type.
  final int? leaveTypeId;

  /// Whether these days were charged to the annual balance — the snapshot
  /// taken when the request was filed, so a later policy change never
  /// rewrites it. Defaults to `true`: that is what an untyped request is
  /// filed as, and what a backend predating types always did.
  final bool deductsBalance;

  /// True when HR filed this on the employee's behalf to justify an absence.
  /// Such a row arrives already `approved` with no `manager_id` — there is no
  /// review step — so it must not be shown as an ordinary approved request
  /// the employee submitted.
  final bool isExcuse;

  /// The HR user who filed an excuse. `null` on self-submitted requests.
  final int? createdBy;

  final String? reason;

  /// Whoever must act now while pending; after the final decision, whoever
  /// made it. This remains the compatibility field for single-approver rows.
  final int? managerId;
  final String? managerName;

  /// Ordered decision chain. Empty on legacy single-approver rows and on an HR
  /// excuse, which is filed already approved and has no review workflow.
  final List<LeaveApprovalStep> approvals;

  /// The approver whose turn it is, or null after a final decision. Kept apart
  /// from [managerId], which deliberately rests on the final actor.
  final int? currentApproverId;

  /// Server-authoritative permission for the viewer. Null means the field was
  /// absent (older backend / cached row), so the UI may use [managerId] as its
  /// backward-compatible fallback; false is an explicit denial.
  final bool? canReview;

  /// The employee who submitted the request (useful on the approvals list).
  final int? requesterId;
  final String? requesterName;

  final DateTime? createdAt;
  final DateTime? reviewedAt;

  final int? _days;

  /// Working days the request covers. Whether they are deducted from the
  /// balance is [deductsBalance], not this number. Prefers the server's
  /// count (`days` / `requested_days`); falls back to a locally computed
  /// working-day count when the backend doesn't send one.
  int get days => _days ?? workingDaysBetween(startDate, endDate);

  bool get isPending => status == LeaveStatus.pending;
  bool get isApproved => status == LeaveStatus.approved;

  /// Whether [userId] may act on this request right now.
  ///
  /// [canReview] is server-authoritative: `false` is an explicit denial, and
  /// only null — an older backend, or a cached row parsed before the field
  /// existed — falls back to the legacy [managerId] equality. The rule lives
  /// here because the detail screen asks it twice, for the waiting banner and
  /// for the action bar, and those two must never answer differently.
  ///
  /// The fallback additionally refuses a viewer whose own step is already
  /// closed. [managerId] is the field the server updates lazily, so a cached
  /// row — or one from a backend that leaves it on the previous approver —
  /// can still name a viewer who has already approved, or whose step a
  /// rejection skipped. Their chain step is the reliable answer, and it is
  /// consulted precisely where the data is least trustworthy: handing them a
  /// live approve button only to have the server answer 422 is worse than
  /// showing them none.
  bool canBeReviewedBy(int? userId) {
    final explicit = canReview;
    if (explicit != null) return explicit;
    if (userId == null || managerId != userId) return false;
    final step = stepFor(userId);
    return step == null || step.isPending;
  }

  /// [approvals] in the order the chain runs.
  ///
  /// Sorted by `approval_order`, but **stably**: a list projection can omit
  /// that field, which [LeaveApprovalStep.fromJson] parses as 0, and every
  /// step sharing that 0 has to keep the order the payload listed them in
  /// rather than whatever an unstable sort leaves behind. Without it the tile
  /// and the detail screen can order the same chain differently.
  List<LeaveApprovalStep> get orderedApprovals {
    final indexed = [
      for (var i = 0; i < approvals.length; i++) (i, approvals[i]),
    ]..sort((a, b) {
        final byOrder = a.$2.approvalOrder.compareTo(b.$2.approvalOrder);
        return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
      });
    return [for (final entry in indexed) entry.$2];
  }

  /// The 1-based step number to display for [step].
  ///
  /// [LeaveApprovalStep.approvalOrder] is 0 when the payload omitted
  /// `approval_order` — a tolerated projection, not an error — so the position
  /// in [orderedApprovals] stands in for it. Every surface that numbers a step
  /// asks here, or one of them renders «الخطوة 0» for a chain the other
  /// numbers correctly.
  int stepNumberOf(LeaveApprovalStep step) => step.approvalOrder > 0
      ? step.approvalOrder
      : orderedApprovals.indexOf(step) + 1;

  /// This viewer's own step in the chain, or null when they hold none — a
  /// plain employee looking at their own request, or a legacy row that has no
  /// chain at all. The step's status is what separates "your turn has not come
  /// yet" from "you already acted"; membership alone cannot.
  LeaveApprovalStep? stepFor(int? userId) {
    if (userId == null) return null;
    for (final step in approvals) {
      if (step.userId == userId) return step;
    }
    return null;
  }

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
    final rawApprovals = json['approvals'];
    return LeaveRequest(
      id: _toInt(json['id']) ?? 0,
      startDate: _toDate(json['start_date']) ?? DateTime.now(),
      endDate: _toDate(json['end_date']) ?? DateTime.now(),
      status: LeaveStatus.fromString(json['status'] as String?),
      leaveType: json['leave_type'] as String?,
      leaveTypeId: _toInt(json['leave_type_id']),
      // Absent on a backend predating types → deducting, the behaviour that
      // applied before the flag existed.
      deductsBalance: _toBool(json['deducts_balance']) ?? true,
      isExcuse: _toBool(json['is_excuse']) ?? false,
      createdBy: _toInt(json['created_by']),
      reason: json['reason'] as String?,
      managerId: _toInt(json['manager_id']) ??
          (manager is Map ? _toInt(manager['id']) : null),
      managerName: manager is Map ? manager['name'] as String? : null,
      approvals: rawApprovals is List
          ? rawApprovals
              .whereType<Map>()
              .map((step) => LeaveApprovalStep.fromJson(
                    step.cast<String, dynamic>(),
                  ))
              .toList()
          : const [],
      currentApproverId: _toInt(json['current_approver_id']),
      canReview: _toBool(json['can_review']),
      requesterId:
          _toInt(json['user_id']) ?? (user is Map ? _toInt(user['id']) : null),
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

/// Inclusive count of WORKING days between [start] and [end] — the duration
/// the backend counts. Mirrors the backend's rule so the form can preview the
/// counted days; with every day currently a working day this equals
/// [daysBetween], and the two are kept apart so the seam survives a calendar
/// that skips days again. A preview only: the server's `requested_days` on
/// the response is the number that counts. Returns 0 if [end] is before
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

/// The Arabic wording for a business rule `POST /attendance/leave-requests`
/// reports in English, or `null` when [serverMessage] is not one of them.
///
/// These three 422s carry no `error` code, so `ApiErrorCode.fromString`
/// resolves them to `unknown` and the raw English message would otherwise be
/// shown verbatim to an Arabic-only user. Matching on the message is the only
/// option the endpoint leaves; when it starts sending a code, switch to that
/// and delete this.
///
/// Deliberately exact (bar whitespace and case): a partial match risks
/// mistranslating a future rule that merely shares a prefix, and an unmatched
/// message falls back to the generic Arabic error, which is wrong but not
/// misleading.
String? arabicLeaveRuleMessage(String? serverMessage) {
  if (serverMessage == null) return null;
  final normalized =
      serverMessage.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  return switch (normalized) {
    'the selected period contains no working days.' =>
      'الفترة المحددة لا تتضمن أي يوم عمل.',
    'leave request exceeds the remaining annual leave balance.' =>
      'طلب الإجازة يتجاوز رصيد الإجازات السنوية المتبقي.',
    'a pending or approved leave request already overlaps this period.' =>
      'يوجد طلب إجازة معلق أو معتمد يتداخل مع هذه الفترة.',
    _ => null,
  };
}

/// Arabic wording for the four untyped 422s `PATCH /leave-requests/{id}/review`
/// answers with, or null when [serverMessage] is none of them.
///
/// Every one of them carries a bare `message` and no `error` code, so
/// `ApiErrorCode.fromString` resolves them to `unknown` and the raw English
/// would otherwise be shown verbatim to an Arabic-only approver. Three of the
/// four are ordinary races rather than edge cases: an approvals list or a push
/// notification goes stale the moment another approver acts, an admin
/// reassigns a step, or the requester's balance is spent between submission
/// and the final approval.
///
/// `not_your_turn` defers to [arabicMessageFor] rather than repeating its
/// wording, since newer backends send that one as a typed code and the two
/// spellings must not drift apart. The rest have no code to defer to.
///
/// Matching is exact (bar whitespace and case), like [arabicLeaveRuleMessage]:
/// a partial match risks mistranslating a future rule that merely shares a
/// prefix, and an unmatched message falls back to the generic Arabic error,
/// which is vague but never wrong. Note the balance sentence here is NOT the
/// one [arabicLeaveRuleMessage] catches — the store-time rule says "the
/// remaining", this one says "the employee remaining" — which is exactly why
/// it slipped through untranslated.
String? arabicLeaveReviewMessage(String? serverMessage) {
  if (serverMessage == null) return null;
  final normalized =
      serverMessage.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  return switch (normalized) {
    'it is not your turn to review this leave request.' =>
      arabicMessageFor(ApiErrorCode.notYourTurn),
    'only pending leave requests can be reviewed.' =>
      'تم البت في هذا الطلب مسبقاً، ولم يعد قابلاً للمراجعة.',
    'this leave request has no pending approval step.' =>
      'لا توجد خطوة موافقة معلقة على هذا الطلب.',
    'leave request exceeds the employee remaining annual leave balance.' =>
      'طلب الإجازة يتجاوز رصيد الإجازات السنوية المتبقي للموظف.',
    _ => null,
  };
}

int? _toInt(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString());
}

/// Reads a backend boolean, which arrives as a real bool from JSON but as
/// `"1"` / `"0"` from an FCM data payload and from the local cache's older
/// rows. `null` means the field was absent, so the caller can apply its own
/// default rather than inheriting `false`.
bool? _toBool(dynamic raw) {
  if (raw == null) return null;
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  return switch (raw.toString().trim().toLowerCase()) {
    'true' || '1' => true,
    'false' || '0' || '' => false,
    _ => null,
  };
}

DateTime? _toDate(dynamic raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toLocal();
}
