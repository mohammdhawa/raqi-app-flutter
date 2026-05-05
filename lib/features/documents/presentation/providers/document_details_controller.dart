import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_failure.dart';
import '../../data/documents_repository.dart';
import '../../domain/document.dart';

class DocumentDetailsState {
  const DocumentDetailsState({
    this.document,
    this.isLoading = false,
    this.isActing = false,
    this.error,
  });

  final Document? document;
  final bool isLoading;

  /// True while an approve/reject is in flight.
  final bool isActing;
  final ApiFailure? error;

  DocumentDetailsState copyWith({
    Document? document,
    bool? isLoading,
    bool? isActing,
    ApiFailure? error,
    bool clearError = false,
  }) =>
      DocumentDetailsState(
        document: document ?? this.document,
        isLoading: isLoading ?? this.isLoading,
        isActing: isActing ?? this.isActing,
        error: clearError ? null : (error ?? this.error),
      );
}

class DocumentDetailsController extends StateNotifier<DocumentDetailsState> {
  DocumentDetailsController(this._repo, this.documentId)
      : super(const DocumentDetailsState(isLoading: true)) {
    load();
  }

  final DocumentsRepository _repo;
  final int documentId;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final doc = await _repo.getById(documentId);
      if (!mounted) return;
      state = DocumentDetailsState(document: doc);
    } on Exception catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: e is ApiFailure ? e : null,
      );
    }
  }

  /// Returns the updated document on success so the caller can also push
  /// it back into the inbox/sent list state.
  Future<Document?> approve({String? note}) async {
    return _act(() => _repo.approve(documentId, note: note));
  }

  Future<Document?> reject({String? note}) async {
    return _act(() => _repo.reject(documentId, note: note));
  }

  Future<Document?> _act(Future<Document> Function() action) async {
    state = state.copyWith(isActing: true, clearError: true);
    try {
      final updated = await action();
      if (!mounted) return updated;
      state = DocumentDetailsState(document: updated);
      return updated;
    } on Exception catch (e) {
      if (!mounted) return null;
      state = state.copyWith(
        isActing: false,
        error: e is ApiFailure ? e : null,
      );
      return null;
    }
  }
}

final documentDetailsProvider = StateNotifierProvider.family<
    DocumentDetailsController, DocumentDetailsState, int>((ref, id) {
  return DocumentDetailsController(
    ref.watch(documentsRepositoryProvider),
    id,
  );
});