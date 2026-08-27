import '../../../../core/errors/api_failure.dart';
import '../../../auth/domain/user.dart';

/// What a submission's `approver_ids` validation errors mean for the form's
/// current selection.
class StaleApproverOutcome {
  const StaleApproverOutcome({
    required this.remaining,
    required this.removed,
    required this.message,
  });

  /// The selection with every rejected approver taken out.
  final List<User> remaining;

  /// The approvers the server refused — named in [message] when known.
  final List<User> removed;

  /// Ready-to-display Arabic explanation for the approver selector.
  final String message;
}

/// Reconciles a rejected submission against the approvers the form still has
/// selected, or null when the failure says nothing about `approver_ids`.
///
/// `/managers` is the source of eligible approvers, but a list fetched a few
/// minutes ago can name somebody who has since been soft-deleted or demoted
/// out of the manager/chief roles. `StoreDocumentRequest` (and its generated
/// twin) validate every id with
/// `exists:users,id … whereNull(deleted_at) … whereIn(role, [manager, chief])`,
/// so that submission comes back as `approver_ids.2` — keyed by POSITION in
/// the array we sent, which is the order of the form's own list.
///
/// The stale entries are dropped rather than left selected: re-submitting the
/// same list fails identically every time, and the picker re-reads `/managers`
/// whenever it opens, so re-picking is what refreshes the roster.
StaleApproverOutcome? resolveStaleApprovers(
  ApiFailure failure,
  List<User> current,
) {
  final messages = failure.errorsForPrefix('approver_ids');
  if (messages.isEmpty) return null;

  final indices = failure.invalidIndicesFor('approver_ids');

  // A bare `approver_ids` error (e.g. "required") names no element, so there
  // is nothing to single out — keep the selection and just report it.
  if (indices.isEmpty) {
    return StaleApproverOutcome(
      remaining: List.of(current),
      removed: const [],
      message: messages.first,
    );
  }

  final removed = <User>[];
  final remaining = <User>[];
  for (var i = 0; i < current.length; i++) {
    if (indices.contains(i)) {
      removed.add(current[i]);
    } else {
      remaining.add(current[i]);
    }
  }

  final names =
      removed.map((u) => u.name).where((n) => n.isNotEmpty).join('، ');
  final detail = names.isEmpty
      ? 'تمت إزالة المعتمدين غير الصالحين من القائمة.'
      : 'تمت إزالة: $names';

  return StaleApproverOutcome(
    remaining: remaining,
    removed: removed,
    message: '${messages.first} $detail '
        'يرجى فتح قائمة المعتمدين واختيار البدلاء ثم التأكيد.',
  );
}
