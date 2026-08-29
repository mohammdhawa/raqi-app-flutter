import '../errors/api_failure.dart';

/// What a submission's `approver_ids` validation errors mean for the form's
/// current selection.
///
/// Generic over the type the form holds its approvers in: the document forms
/// select `User`s and the leave form selects `LeaveManager`s, but the server
/// contract they are reconciling against is the same one, so the reconciliation
/// is too.
class StaleApproverOutcome<T> {
  const StaleApproverOutcome({
    required this.remaining,
    required this.removed,
    required this.message,
  });

  /// The selection with every rejected approver taken out.
  final List<T> remaining;

  /// The approvers the server refused — named in [message] when known.
  final List<T> removed;

  /// Ready-to-display Arabic explanation for the approver selector.
  final String message;
}

/// Reconciles a rejected submission against the approvers the form still has
/// selected, or null when the failure says nothing about `approver_ids`.
///
/// The eligible-approver roster (`/managers`, `/attendance/leave-managers`) is
/// a snapshot: a list fetched a few minutes ago can name somebody who has
/// since been soft-deleted or demoted out of the manager/chief roles.
/// `StoreDocumentRequest`, its generated twin and `StoreLeaveRequest` all
/// validate every id with
/// `exists:users,id … whereNull(deleted_at) … whereIn(role, [manager, chief])`,
/// so that submission comes back as `approver_ids.2` — keyed by POSITION in
/// the array we sent, which is the order of the form's own list.
///
/// The stale entries are dropped rather than left selected: re-submitting the
/// same list fails identically every time, and the picker re-reads the roster
/// whenever it opens, so re-picking is what refreshes it.
///
/// [nameOf] supplies the display name for the message; return an empty string
/// for an approver whose name the payload never carried, and it is left out of
/// the list rather than named as a placeholder glyph.
StaleApproverOutcome<T>? resolveStaleApprovers<T>(
  ApiFailure failure,
  List<T> current, {
  required String Function(T approver) nameOf,
}) {
  final messages = failure.errorsForPrefix('approver_ids');
  if (messages.isEmpty) return null;

  final indices = failure.invalidIndicesFor('approver_ids');

  // A bare `approver_ids` error (e.g. "required") names no element, so there
  // is nothing to single out — keep the selection and just report it.
  if (indices.isEmpty) {
    return StaleApproverOutcome<T>(
      remaining: List.of(current),
      removed: const [],
      message: messages.first,
    );
  }

  final removed = <T>[];
  final remaining = <T>[];
  for (var i = 0; i < current.length; i++) {
    if (indices.contains(i)) {
      removed.add(current[i]);
    } else {
      remaining.add(current[i]);
    }
  }

  final names = removed.map(nameOf).where((n) => n.isNotEmpty).join('، ');
  final detail = names.isEmpty
      ? 'تمت إزالة المعتمدين غير الصالحين من القائمة.'
      : 'تمت إزالة: $names';

  return StaleApproverOutcome<T>(
    remaining: remaining,
    removed: removed,
    message: '${messages.first} $detail '
        'يرجى فتح قائمة المعتمدين واختيار البدلاء ثم التأكيد.',
  );
}
