import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_failure.dart';
import '../../data/documents_repository.dart';
import '../../domain/document.dart';

/// Listing state: items + paging cursors + load flags.
class DocumentsListState {
  const DocumentsListState({
    this.documents = const [],
    this.currentPage = 0,
    this.lastPage = 1,
    this.total = 0,
    this.isLoadingFirstPage = false,
    this.isLoadingMore = false,
    this.isRefreshing = false,
    this.statusFilter = DocumentStatusFilter.all,
    this.error,
  });

  final List<Document> documents;
  final int currentPage;
  final int lastPage;
  final int total;
  final bool isLoadingFirstPage;
  final bool isLoadingMore;
  final bool isRefreshing;
  final DocumentStatusFilter statusFilter;
  final ApiFailure? error;

  bool get isEmpty =>
      documents.isEmpty &&
      !isLoadingFirstPage &&
      !isRefreshing &&
      error == null;
  bool get hasMore => currentPage < lastPage;

  DocumentsListState copyWith({
    List<Document>? documents,
    int? currentPage,
    int? lastPage,
    int? total,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    bool? isRefreshing,
    DocumentStatusFilter? statusFilter,
    ApiFailure? error,
    bool clearError = false,
  }) =>
      DocumentsListState(
        documents: documents ?? this.documents,
        currentPage: currentPage ?? this.currentPage,
        lastPage: lastPage ?? this.lastPage,
        total: total ?? this.total,
        isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        statusFilter: statusFilter ?? this.statusFilter,
        error: clearError ? null : (error ?? this.error),
      );
}

class DocumentsListController extends StateNotifier<DocumentsListState> {
  DocumentsListController(this._repo, this.type)
      : super(const DocumentsListState()) {
    refresh();
  }

  final DocumentsRepository _repo;
  final DocumentListType type;

  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true, clearError: true);
    try {
      final page = await _repo.list(
        type: type,
        page: 1,
        statusFilter: state.statusFilter,
      );
      if (!mounted) return;
      state = DocumentsListState(
        documents: page.documents,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
        statusFilter: state.statusFilter,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isRefreshing: false,
        isLoadingFirstPage: false,
        error: e is ApiFailure ? e : null,
      );
    }
  }

  Future<void> loadFirstPageIfEmpty() async {
    if (state.documents.isNotEmpty || state.isLoadingFirstPage) return;
    state = state.copyWith(isLoadingFirstPage: true, clearError: true);
    try {
      final page = await _repo.list(
        type: type,
        page: 1,
        statusFilter: state.statusFilter,
      );
      if (!mounted) return;
      state = DocumentsListState(
        documents: page.documents,
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
        statusFilter: state.statusFilter,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoadingFirstPage: false,
        error: e is ApiFailure ? e : null,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final page = await _repo.list(
        type: type,
        page: state.currentPage + 1,
        statusFilter: state.statusFilter,
      );
      if (!mounted) return;
      state = state.copyWith(
        documents: [...state.documents, ...page.documents],
        currentPage: page.currentPage,
        lastPage: page.lastPage,
        total: page.total,
        isLoadingMore: false,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoadingMore: false,
        error: e is ApiFailure ? e : null,
      );
    }
  }

  /// Changes the status filter and reloads page 1.
  Future<void> setStatusFilter(DocumentStatusFilter filter) async {
    if (state.statusFilter == filter) return;
    state = DocumentsListState(statusFilter: filter);
    await refresh();
  }

  /// Replace a document in the list (after approve/reject completes).
  /// No-op if the id isn't in our list.
  void replaceDocument(Document updated) {
    var found = false;
    final next = <Document>[];
    for (final d in state.documents) {
      if (d.id == updated.id) {
        next.add(updated);
        found = true;
      } else {
        next.add(d);
      }
    }
    if (!found) return;
    state = state.copyWith(documents: next);
  }

  /// Remove a document from the list (after it has been deleted).
  /// No-op if the id isn't in our list.
  void removeDocument(int id) {
    final next = state.documents.where((d) => d.id != id).toList();
    if (next.length == state.documents.length) return;
    state = state.copyWith(
      documents: next,
      total: state.total > 0 ? state.total - 1 : 0,
    );
  }
}

/// Family of controllers — one per list type (inbox / sent).
final documentsListProvider = StateNotifierProvider.autoDispose.family<
    DocumentsListController,
    DocumentsListState,
    DocumentListType>((ref, type) {
  return DocumentsListController(
    ref.watch(documentsRepositoryProvider),
    type,
  );
});