import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_failure.dart';
import '../../data/documents_repository.dart';
import '../../domain/document.dart';

class DocumentDetailsState {
  const DocumentDetailsState({
    this.document,
    this.isLoading = false,
    this.isActing = false,
    this.isDeleting = false,
    this.error,
  });

  final Document? document;
  final bool isLoading;

  /// True while an approve/reject is in flight.
  final bool isActing;

  /// True while a delete request is in flight.
  final bool isDeleting;
  final ApiFailure? error;

  DocumentDetailsState copyWith({
    Document? document,
    bool? isLoading,
    bool? isActing,
    bool? isDeleting,
    ApiFailure? error,
    bool clearError = false,
  }) =>
      DocumentDetailsState(
        document: document ?? this.document,
        isLoading: isLoading ?? this.isLoading,
        isActing: isActing ?? this.isActing,
        isDeleting: isDeleting ?? this.isDeleting,
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

  Future<Document?> approve({String? note}) async {
    final r = await _act(() => _repo.approve(documentId, note: note));
    return r;
  }

  Future<Document?> reject({String? note}) async {
    final r = await _act(() => _repo.reject(documentId, note: note));
    return r;
  }

  /// Returns true on success, false on failure (error stored in state).
  Future<bool> delete() async {
    state = state.copyWith(isDeleting: true, clearError: true);
    try {
      await _repo.delete(documentId);
      if (!mounted) return true;
      state = state.copyWith(isDeleting: false);
      return true;
    } on Exception catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        isDeleting: false,
        error: e is ApiFailure ? e : null,
      );
      return false;
    }
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