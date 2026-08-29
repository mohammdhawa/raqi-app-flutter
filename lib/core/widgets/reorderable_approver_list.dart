import 'package:flutter/material.dart';

/// The drag affordance for one row of a [ReorderableApproverList].
///
/// Handed to the row builder so each form can place the handle in its own
/// layout — the rows differ between forms, the way they reorder does not.
class ApproverReorder {
  const ApproverReorder._(this._index);

  final int _index;

  /// Wraps [child] so dragging it starts a reorder of this row.
  Widget handle(Widget child) =>
      ReorderableDragStartListener(index: _index, child: child);
}

/// The ordered approver chain a submission form shows above its submit button.
///
/// Three forms pick a chain — a document, a generated document and a leave
/// request — and each had grown its own copy of this list. The rows differ for
/// real (a chief badge on one, a per-row 422 message on another), so they stay
/// with their screens; the list around them does not, and lives here.
///
/// Reordering goes through [ReorderableListView.onReorderItem], which already
/// accounts for the dragged row leaving its old position. The deprecated
/// `onReorder` it replaces reports a destination index every caller had to
/// correct with the same `if (newIndex > oldIndex) newIndex -= 1` line, and a
/// copy that forgets it produces a silently wrong chain rather than an error.
///
/// Known limitation: the list shrink-wraps inside the form's own scroll view
/// and so has no scrollable extent of its own, which disables the auto-scroll
/// a ReorderableListView normally performs when a drag reaches its edge. A
/// chain long enough to overflow the viewport therefore takes several short
/// drags to rearrange end to end rather than one. Fixing that properly means
/// making the form body a CustomScrollView and this a SliverReorderableList,
/// so the drag drives the outer scrollable; adding per-row move buttons was
/// tried instead and rejected as visual clutter.
class ReorderableApproverList extends StatelessWidget {
  const ReorderableApproverList({
    super.key,
    required this.itemCount,
    required this.itemKey,
    required this.itemBuilder,
    required this.onReorder,
    this.proxyDecorator,
  });

  final int itemCount;

  /// A stable identity for the row at `index` — the approver's id, never its
  /// position, or a reorder animates the wrong row back into place.
  final Key Function(int index) itemKey;

  /// Builds the row at `index`. The [ApproverReorder] carries this row's drag
  /// handle.
  final Widget Function(
    BuildContext context,
    int index,
    ApproverReorder reorder,
  ) itemBuilder;

  /// Called with the row's old and new positions, already adjusted — insert at
  /// `newIndex` after removing `oldIndex` and the result is what the user saw.
  final void Function(int oldIndex, int newIndex) onReorder;

  final ReorderItemProxyDecorator? proxyDecorator;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // Every form marks its own drag affordance, so the whole-row long press
      // is off: on the document form only a sequential chain is draggable at
      // all, and a long press on a parallel one must not appear to reorder it.
      buildDefaultDragHandles: false,
      itemCount: itemCount,
      onReorderItem: onReorder,
      proxyDecorator: proxyDecorator,
      itemBuilder: (context, index) => KeyedSubtree(
        key: itemKey(index),
        child: itemBuilder(context, index, ApproverReorder._(index)),
      ),
    );
  }
}
