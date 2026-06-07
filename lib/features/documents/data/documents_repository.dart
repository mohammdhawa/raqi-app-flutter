import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/api_failure.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/user.dart';
import '../domain/document.dart';
import '../domain/document_template.dart';

enum DocumentListType {
  inbox,
  sent;

  String get apiValue => name;
}

/// Suggested next counters returned by `GET /document-counters/next`.
class DocumentCounters {
  const DocumentCounters({
    required this.departmentId,
    this.exportNextNumber,
    required this.exportIsInitialized,
    this.importNextNumber,
  });

  final int departmentId;
  final int? exportNextNumber;
  final bool exportIsInitialized;
  final int? importNextNumber;

  factory DocumentCounters.fromJson(Map<String, dynamic> json) {
    final exp = json['export'] as Map<String, dynamic>;
    final imp = json['import'] as Map<String, dynamic>?;
    return DocumentCounters(
      departmentId: (json['department_id'] as num).toInt(),
      exportNextNumber: (exp['next_number'] as num?)?.toInt(),
      exportIsInitialized: exp['is_initialized'] as bool,
      importNextNumber: (imp?['next_number'] as num?)?.toInt(),
    );
  }
}

class TemplatesPage {
  const TemplatesPage({
    required this.templates,
    required this.currentPage,
    required this.lastPage,
  });
  final List<DocumentTemplate> templates;
  final int currentPage;
  final int lastPage;
}

/// Wraps every document-related endpoint from sections 5 and 6 of the API
/// docs. Returns parsed domain objects; throws [ApiFailure] on errors
/// (mapped by the [ApiClient] interceptor).
class DocumentsRepository {
  DocumentsRepository(this._api);

  final ApiClient _api;

  // Dio rejects with DioException(error: ApiFailure); unwrap so callers can
  // use `on ApiFailure catch` directly.
  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      if (e.error is ApiFailure) throw e.error as ApiFailure;
      rethrow;
    }
  }

  /// `GET /documents?type=inbox|sent&page=N`
  Future<DocumentsPage> list({
    required DocumentListType type,
    int page = 1,
  }) async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
      '/documents',
      queryParameters: {'type': type.apiValue, 'page': page},
    ));
    return DocumentsPage.fromJson(response.data!);
  }

  /// `GET /documents/{id}`
  Future<Document> getById(int id) async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
      '/documents/$id',
    ));
    return _parseDocumentEnvelope(response.data!);
  }

  /// `POST /documents` — multipart upload. Returns the freshly-created
  /// document (with logs already populated for created + sent).
  Future<Document> create({
    required String title,
    String? description,
    required File file,
    required WorkflowMode workflowMode,
    required List<int> approverIds,
  }) async {
    final form = FormData.fromMap({
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      'workflow_mode': workflowMode.apiValue,
      'approver_ids[]': approverIds,
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.path.split(Platform.pathSeparator).last,
      ),
    });

    final response = await _run(() => _api.dio.post(
      '/documents',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    ));

    debugPrint('=== CREATE RESPONSE ===');
    debugPrint('Status: ${response.statusCode}');
    debugPrint('Data type: ${response.data.runtimeType}');
    debugPrint('Data: ${response.data}');

    final data = response.data;

    if (data == null) {
      throw Exception('Server returned null — status ${response.statusCode}');
    }

    if (data is! Map<String, dynamic>) {
      throw Exception('Unexpected response type: ${data.runtimeType} — $data');
    }

    return _parseDocumentEnvelope(data);
  } 

  // ── Counter endpoint ──────────────────────────────────────────────

  /// `GET /document-counters/next`
  Future<DocumentCounters> fetchNextCounters() async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
      '/document-counters/next',
    ));
    return DocumentCounters.fromJson(response.data!);
  }

  // ── Template endpoints ───────────────────────────────────────────

  /// `GET /document-templates?search=&page=`
  Future<TemplatesPage> fetchTemplates({String? search, int page = 1}) async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
      '/document-templates',
      queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        'page': page,
      },
    ));
    final paginator = response.data!['templates'] as Map<String, dynamic>;
    final templates = ((paginator['data'] as List?) ?? [])
        .map((e) => DocumentTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
    return TemplatesPage(
      templates: templates,
      currentPage: (paginator['current_page'] as num).toInt(),
      lastPage: (paginator['last_page'] as num).toInt(),
    );
  }

  /// `POST /documents/generated` — JSON payload (no file upload).
  /// The backend renders the PDF from the template + field values,
  /// then feeds it into the same workflow as uploaded documents.
  Future<Document> createGenerated({
    required int templateId,
    required String title,
    String? description,
    required Map<String, dynamic> fieldValues,
    required WorkflowMode workflowMode,
    required List<int> approverIds,
    int? exportNumber,
    int? importNumber,
  }) async {
    final response = await _run(() => _api.dio.post<Map<String, dynamic>>(
      '/documents/generated',
      data: {
        'template_id': templateId,
        'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        'field_values': fieldValues,
        'workflow_mode': workflowMode.apiValue,
        'approver_ids': approverIds,
        if (exportNumber != null) 'export_number': exportNumber,
        if (importNumber != null) 'import_number': importNumber,
      },
    ));

    final data = response.data;
    if (data == null) {
      throw Exception('Server returned null — status ${response.statusCode}');
    }
    return _parseDocumentEnvelope(data);
  }

  /// `POST /documents/{id}/approve`
  Future<Document> approve(int id, {String? note}) async {
    final response = await _run(() => _api.dio.post<Map<String, dynamic>>(
      '/documents/$id/approve',
      data: {if (note != null && note.isNotEmpty) 'note': note},
    ));
    return _parseDocumentEnvelope(response.data!);
  }

  /// `GET /documents/{id}/comments`
  Future<List<DocumentComment>> getComments(int documentId) async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
      '/documents/$documentId/comments',
    ));
    final data = (response.data!['data'] as List?) ?? [];
    return data
        .map((e) => DocumentComment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `POST /documents/{id}/comments`
  Future<DocumentComment> addComment(
    int documentId, {
    required String comment,
    String visibility = 'all',
  }) async {
    final response = await _run(() => _api.dio.post<Map<String, dynamic>>(
      '/documents/$documentId/comments',
      data: {'comment': comment, 'visibility': visibility},
    ));
    final body = response.data!;
    final commentJson =
        body['data'] is Map ? body['data'] as Map<String, dynamic> : body;
    return DocumentComment.fromJson(commentJson);
  }

  /// `POST /documents/{id}/reject`
  Future<Document> reject(int id, {String? note}) async {
    final response = await _run(() => _api.dio.post<Map<String, dynamic>>(
      '/documents/$id/reject',
      data: {if (note != null && note.isNotEmpty) 'note': note},
    ));
    return _parseDocumentEnvelope(response.data!);
  }

  /// Helper: the API wraps the document object in `{ document, ... }` for
  /// details, create, approve, and reject. Some responses also include a
  /// top-level `next_pending_users` array.
  Document _parseDocumentEnvelope(Map<String, dynamic> json) {
    final docJson = json['document'] as Map<String, dynamic>?;
    if (docJson == null) {
      throw Exception(
        'Response missing "document" key. Raw response: $json',
      );
    }
    final nextPending = ((json['next_pending_users'] as List?) ?? [])
        .map((e) => User.fromJson(e as Map<String, dynamic>))
        .toList();
    return Document.fromJson(docJson, nextPendingUsers: nextPending);
  }
}

final documentsRepositoryProvider = Provider<DocumentsRepository>((ref) {
  return DocumentsRepository(ref.watch(apiClientProvider));
});