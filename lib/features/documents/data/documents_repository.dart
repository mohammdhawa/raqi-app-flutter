import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../auth/domain/user.dart';
import '../domain/document.dart';

enum DocumentListType {
  inbox,
  sent;

  String get apiValue => name;
}

/// Wraps every document-related endpoint from sections 5 and 6 of the API
/// docs. Returns parsed domain objects; throws [ApiFailure] on errors
/// (mapped by the [ApiClient] interceptor).
class DocumentsRepository {
  DocumentsRepository(this._api);

  final ApiClient _api;

  /// `GET /documents?type=inbox|sent&page=N`
  Future<DocumentsPage> list({
    required DocumentListType type,
    int page = 1,
  }) async {
    final response = await _api.dio.get<Map<String, dynamic>>(
      '/documents',
      queryParameters: {'type': type.apiValue, 'page': page},
    );
    return DocumentsPage.fromJson(response.data!);
  }

  /// `GET /documents/{id}`
  Future<Document> getById(int id) async {
    final response = await _api.dio.get<Map<String, dynamic>>(
      '/documents/$id',
    );
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

    final response = await _api.dio.post(
      '/documents',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );

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

  /// `POST /documents/{id}/approve`
  Future<Document> approve(int id, {String? note}) async {
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/documents/$id/approve',
      data: {if (note != null && note.isNotEmpty) 'note': note},
    );
    return _parseDocumentEnvelope(response.data!);
  }

  /// `POST /documents/{id}/reject`
  Future<Document> reject(int id, {String? note}) async {
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/documents/$id/reject',
      data: {if (note != null && note.isNotEmpty) 'note': note},
    );
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
