import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/documents_repository.dart';
import '../../domain/document.dart';

class DocumentCommentsState {
  const DocumentCommentsState({
    this.comments = const [],
    this.isLoading = false,
    this.isPosting = false,
    this.hasLoaded = false,
  });

  final List<DocumentComment> comments;
  final bool isLoading;
  final bool isPosting;
  final bool hasLoaded;

  DocumentCommentsState copyWith({
    List<DocumentComment>? comments,
    bool? isLoading,
    bool? isPosting,
    bool? hasLoaded,
  }) =>
      DocumentCommentsState(
        comments: comments ?? this.comments,
        isLoading: isLoading ?? this.isLoading,
        isPosting: isPosting ?? this.isPosting,
        hasLoaded: hasLoaded ?? this.hasLoaded,
      );
}

class DocumentCommentsController
    extends StateNotifier<DocumentCommentsState> {
  DocumentCommentsController(this._repo, this.documentId)
      : super(const DocumentCommentsState());

  final DocumentsRepository _repo;
  final int documentId;

  Future<void> load() async {
    if (state.hasLoaded) return;
    state = state.copyWith(isLoading: true);
    try {
      final comments = await _repo.getComments(documentId);
      if (!mounted) return;
      state = state.copyWith(
        comments: comments,
        isLoading: false,
        hasLoaded: true,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, hasLoaded: true);
    }
  }

  Future<DocumentComment?> addComment({
    required String comment,
    required String visibility,
  }) async {
    state = state.copyWith(isPosting: true);
    try {
      final result = await _repo.addComment(
        documentId,
        comment: comment,
        visibility: visibility,
      );
      if (!mounted) return null;
      state = state.copyWith(
        isPosting: false,
        comments: [...state.comments, result],
      );
      return result;
    } catch (_) {
      if (!mounted) return null;
      state = state.copyWith(isPosting: false);
      return null;
    }
  }
}

final documentCommentsProvider = StateNotifierProvider.family<
    DocumentCommentsController, DocumentCommentsState, int>((ref, id) {
  return DocumentCommentsController(
    ref.watch(documentsRepositoryProvider),
    id,
  );
});
