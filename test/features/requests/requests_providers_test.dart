import 'package:doc_approval/features/attendance/data/leave_repository.dart';
import 'package:doc_approval/features/attendance/domain/leave.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:doc_approval/features/documents/data/documents_repository.dart';
import 'package:doc_approval/features/documents/domain/document.dart';
import 'package:doc_approval/features/requests/presentation/providers/requests_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class ThrowingDocumentsRepository extends Fake implements DocumentsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      fail('documents repository must not be called');
}

class _InboxRepository extends Fake implements DocumentsRepository {
  _InboxRepository(this.docs);
  final List<Document> docs;

  @override
  Future<DocumentsPage> list({
    required DocumentListType type,
    int page = 1,
    DocumentStatusFilter statusFilter = DocumentStatusFilter.all,
  }) async =>
      DocumentsPage(
          documents: docs, currentPage: 1, lastPage: 1, total: docs.length);
}

class _LeaveRepository extends Fake implements LeaveRepository {
  _LeaveRepository(this.queue);
  final List<LeaveRequest> queue;

  @override
  Future<List<LeaveRequest>> approvals({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? perPage,
  }) async =>
      queue;

  @override
  Future<List<LeaveRequest>> myRequests({
    LeaveStatusFilter status = LeaveStatusFilter.all,
    int? year,
    int? perPage,
  }) async =>
      const [];
}

Document _doc(int id, int managerId) => Document.fromJson({
      'id': id,
      'title': 'مستند $id',
      'status': 'pending',
      'created_at': '2026-10-02T10:00:00',
      'workflows': [
        {
          'id': id,
          'user_id': managerId,
          'order': 1,
          'role': 'manager',
          'status': 'pending',
          'user': {'id': managerId, 'name': 'م$managerId'},
        },
      ],
    });

void main() {
  test('role-less user has an empty inbox and no document fetch', () async {
    final c = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(const User(id: 7, name: 'x')),
      documentsRepositoryProvider
          .overrideWithValue(ThrowingDocumentsRepository()),
    ]);
    addTearDown(c.dispose);
    expect(c.read(canReviewRequestsProvider), isFalse);
    expect(await c.read(documentsAwaitingMeProvider.future), isEmpty);
    expect(c.read(sentDocumentsProvider).requireValue.documents, isEmpty);
    expect(c.read(inboxFeedProvider).valueOrNull, isEmpty);
    expect(c.read(pendingDecisionsCountProvider), 0);
  });

  test('manager inbox counts only documents awaiting them', () async {
    final c = ProviderContainer(overrides: [
      currentUserProvider
          .overrideWithValue(const User(id: 7, name: 'x', role: 'manager')),
      documentsRepositoryProvider
          .overrideWithValue(_InboxRepository([_doc(1, 7), _doc(2, 8)])),
      leaveRepositoryProvider.overrideWithValue(_LeaveRepository(const [])),
    ]);
    addTearDown(c.dispose);
    c.listen(inboxFeedProvider, (_, __) {});
    await c.read(documentsAwaitingMeProvider.future);
    await Future<void>.delayed(Duration.zero);
    final feed = c.read(inboxFeedProvider).requireValue;
    expect(feed.map((i) => i.id), [1]);
    expect(c.read(pendingDecisionsCountProvider), 1);
  });
}
