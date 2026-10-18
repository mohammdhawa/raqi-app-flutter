import 'package:doc_approval/core/services/personal_data_refresh.dart';
import 'package:doc_approval/features/attendance/data/leave_repository.dart';
import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:doc_approval/features/documents/data/documents_repository.dart';
import 'package:doc_approval/features/documents/domain/document.dart';
import 'package:doc_approval/features/documents/presentation/providers/document_details_controller.dart';
import 'package:doc_approval/features/requests/presentation/providers/requests_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = User(id: 7, name: 'م', role: 'manager');

Document _doc({required bool approved}) => Document.fromJson({
      'id': 1,
      'title': 'مستند 1',
      'status': approved ? 'approved' : 'pending',
      'created_at': '2026-10-02T10:00:00',
      'workflows': [
        {
          'id': 1,
          'user_id': _me.id,
          'order': 1,
          'role': 'manager',
          'status': approved ? 'approved' : 'pending',
          'user': {'id': _me.id, 'name': _me.name},
        },
      ],
    });

/// One document waiting on [_me] until it is approved.
class _OneDecisionRepo extends Fake implements DocumentsRepository {
  bool approved = false;

  @override
  Future<Document> getById(int id) async => _doc(approved: approved);

  @override
  Future<Document> approve(int id, {String? note}) async {
    approved = true;
    return _doc(approved: true);
  }

  @override
  Future<DocumentsPage> list({
    required DocumentListType type,
    int page = 1,
    DocumentStatusFilter statusFilter = DocumentStatusFilter.all,
  }) async {
    final docs = type == DocumentListType.inbox && !approved
        ? [_doc(approved: false)]
        : <Document>[];
    return DocumentsPage(
        documents: docs, currentPage: 1, lastPage: 1, total: docs.length);
  }
}

class _NoLeaves extends Fake implements LeaveRepository {
  @override
  Future<List<LeaveRequest>> approvals({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? perPage,
  }) async =>
      const [];
}

void main() {
  // The details screen used to patch documentsListProvider, which nothing
  // watches since the tab shell; the home card and the tab badge kept
  // counting a document already decided.
  testWidgets('approving a document drops it from the pending count',
      (t) async {
    final repo = _OneDecisionRepo();
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(_me),
      documentsRepositoryProvider.overrideWithValue(repo),
      leaveRepositoryProvider.overrideWithValue(_NoLeaves()),
    ]);
    addTearDown(c.dispose);
    c.listen(pendingDecisionsCountProvider, (_, __) {});
    c.listen(documentDetailsProvider(1), (_, __) {});
    late WidgetRef ref;
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: Consumer(builder: (_, r, __) {
        ref = r;
        return const SizedBox.shrink();
      }),
    ));
    await t.pumpAndSettle();
    expect(c.read(pendingDecisionsCountProvider), 1);

    await c.read(documentDetailsProvider(1).notifier).approve();
    await t.pumpAndSettle();
    expect(c.read(pendingDecisionsCountProvider), 1,
        reason: 'the feed is cached until something invalidates it');

    // What the details screen now does after a decision.
    refreshDocumentFeeds(ref);
    await t.pumpAndSettle();
    expect(c.read(pendingDecisionsCountProvider), 0);
  });
}
