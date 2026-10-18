import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_failure.dart';
import '../../../attendance/domain/leave.dart';
import '../../../attendance/presentation/providers/leave_providers.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../../documents/data/documents_repository.dart';
import '../../../documents/domain/document.dart';
import '../../domain/request_item.dart';

/// Pages of the document inbox scanned for "waiting on me". The list endpoint
/// cannot filter by approver, so this bounds the work.
const _maxInboxPages = 5;

/// Only a known document role gets approver or document affordances.
final canReviewRequestsProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider)?.canUseDocumentWorkflow ?? false;
});

/// The documents I sent, loaded a page at a time.
class SentDocuments {
  const SentDocuments({
    this.documents = const [],
    this.page = 0,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  /// Every loaded page, in server order (newest first).
  final List<Document> documents;

  /// The last page loaded; 0 before the first.
  final int page;
  final bool hasMore;
  final bool isLoadingMore;
}

/// Pages through `GET /documents?type=sent`. The first page loads on creation;
/// [loadMore] appends the next one. Older pages matter beyond the documents
/// themselves: while documents are unloaded, the merged طلباتي list hides
/// leaves older than the oldest loaded document (see [mergeRequests]).
class SentDocumentsController extends StateNotifier<AsyncValue<SentDocuments>> {
  SentDocumentsController(this._repo, {required bool enabled})
      : super(enabled
            ? const AsyncLoading()
            : const AsyncData(SentDocuments())) {
    if (enabled) _loadFirst();
  }

  final DocumentsRepository _repo;

  Future<void> _loadFirst() async {
    final next = await AsyncValue.guard(() async {
      final p = await _repo.list(type: DocumentListType.sent);
      return SentDocuments(
          documents: p.documents, page: p.currentPage, hasMore: p.hasMore);
    });
    if (mounted) state = next;
  }

  /// Loads the next page. A failure keeps what is loaded and leaves
  /// `hasMore` set, so the user can simply try again.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;
    state = AsyncData(SentDocuments(
      documents: current.documents,
      page: current.page,
      hasMore: true,
      isLoadingMore: true,
    ));
    try {
      final p = await _repo.list(
          type: DocumentListType.sent, page: current.page + 1);
      if (!mounted) return;
      state = AsyncData(SentDocuments(
        documents: [...current.documents, ...p.documents],
        page: p.currentPage,
        hasMore: p.hasMore,
      ));
    } on ApiFailure {
      if (mounted) state = AsyncData(current);
    }
  }
}

/// Documents the user sent. Empty without a document role, and without
/// touching the network. Invalidate it to start again from page 1.
final sentDocumentsProvider = StateNotifierProvider.autoDispose<
    SentDocumentsController, AsyncValue<SentDocuments>>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return SentDocumentsController(
    ref.watch(documentsRepositoryProvider),
    enabled: ref.watch(canReviewRequestsProvider),
  );
});

/// Whether older sent documents are still unloaded — drives «عرض المزيد».
final sentDocumentsHaveMoreProvider = Provider.autoDispose<bool>((ref) {
  return ref.watch(sentDocumentsProvider).valueOrNull?.hasMore ?? false;
});

/// Pending inbox documents whose turn is the current user's.
final documentsAwaitingMeProvider =
    FutureProvider.autoDispose<List<Document>>((ref) async {
  final me = ref.watch(currentUserProvider);
  if (me == null || !ref.watch(canReviewRequestsProvider)) return const [];
  final repo = ref.watch(documentsRepositoryProvider);
  final mine = <Document>[];
  for (var page = 1; page <= _maxInboxPages; page++) {
    final result = await repo.list(
      type: DocumentListType.inbox,
      page: page,
      statusFilter: DocumentStatusFilter.pending,
    );
    mine.addAll(result.documents.where((d) => isAwaitingUser(d, me.id)));
    if (!result.hasMore) break;
  }
  return mine;
});

List<RequestItem> _leaveItems(Ref ref, Iterable<LeaveRequest> leaves) => [
      for (final r in leaves)
        requestFromLeave(
          r,
          typeLabel: ref.watch(leaveTypeByIdProvider(r.leaveTypeId))?.label,
        ),
    ];

/// Joins a leave list and a document source into one feed state: loading while
/// a source has nothing yet and is still loading, error when a source failed
/// and nothing is loaded, otherwise whatever did load.
AsyncValue<List<RequestItem>> _feed({
  required LeaveListState leaves,
  required List<RequestItem> leaveItems,
  required AsyncValue<List<RequestItem>> documents,
  required bool documentsHaveMore,
}) {
  final leavesFailed = leaves.error != null && leaves.requests.isEmpty;
  final leavesLoading = !leaves.hasLoadedOnce && leaves.error == null;
  final leavesLoaded = !leavesLoading && !leavesFailed;

  if (leavesLoading || (documents.isLoading && !documents.hasValue)) {
    return const AsyncLoading();
  }
  if (!leavesLoaded && !documents.hasValue) {
    return AsyncError(
      leaves.error ?? documents.error ?? 'unknown',
      documents.stackTrace ?? StackTrace.current,
    );
  }
  return AsyncData(mergeRequests(
    leavesLoaded ? leaveItems : const [],
    documents.valueOrNull ?? const [],
    documentsHaveMore: documentsHaveMore,
  ));
}

/// What I filed: my leave requests plus the documents I sent.
final myRequestsFeedProvider =
    Provider.autoDispose<AsyncValue<List<RequestItem>>>((ref) {
  final leaves = ref.watch(myLeaveRequestsProvider);
  final sent = ref.watch(sentDocumentsProvider);
  return _feed(
    leaves: leaves,
    leaveItems: _leaveItems(ref, leaves.requests),
    documents: sent
        .whenData((p) => [for (final d in p.documents) requestFromDocument(d)]),
    documentsHaveMore: ref.watch(sentDocumentsHaveMoreProvider),
  );
});

/// What waits on my decision: leave approvals I may review plus documents
/// whose turn is mine. Empty for users without a document role.
final inboxFeedProvider =
    Provider.autoDispose<AsyncValue<List<RequestItem>>>((ref) {
  if (!ref.watch(canReviewRequestsProvider)) return const AsyncData([]);
  final me = ref.watch(currentUserProvider)?.id;
  final leaves = ref.watch(leaveApprovalsProvider);
  final awaiting = ref.watch(documentsAwaitingMeProvider);
  return _feed(
    leaves: leaves,
    leaveItems: _leaveItems(ref, [
      for (final r in leaves.requests)
        if (r.isPending && r.canBeReviewedBy(me)) r,
    ]),
    documents:
        awaiting.whenData((ds) => [for (final d in ds) requestFromDocument(d)]),
    documentsHaveMore: false,
  );
});

/// Count behind the home screen card and the tab badge.
final pendingDecisionsCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(inboxFeedProvider).valueOrNull?.length ?? 0;
});
