import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:doc_approval/core/errors/api_failure.dart';
import 'package:doc_approval/core/network/api_client.dart';
import 'package:doc_approval/core/storage/token_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Returns one canned response for every request.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  final int statusCode;
  final String body;
  final Map<String, List<String>> headers;

  /// The request the client actually sent — used to inspect its headers.
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeTokenStorage extends Fake implements TokenStorage {
  _FakeTokenStorage([this.token]);

  String? token;
  int clearCount = 0;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> clear() async {
    clearCount++;
    token = null;
  }
}

void main() {
  /// Issues one GET through the real ApiClient and returns the mapped failure.
  Future<ApiFailure> failureFor({
    required int statusCode,
    required String body,
    Map<String, List<String>> headers = const {},
    String? token,
  }) async {
    final adapter = _CannedAdapter(
      statusCode: statusCode,
      body: body,
      headers: headers,
    );
    final client = ApiClient(
      tokenStorage: _FakeTokenStorage(token),
      onUnauthenticated: () {},
    );
    client.dio.httpClientAdapter = adapter;
    try {
      await client.dio.get<Map<String, dynamic>>('/anything');
      fail('expected the client to reject a $statusCode response');
    } on DioException catch (e) {
      return e.error as ApiFailure;
    }
  }

  group('typed backend error codes', () {
    test('the four v10 codes each map to their own enum value', () async {
      final cases = {
        'document_generation_disabled': ApiErrorCode.documentGenerationDisabled,
        'duplicate_export_number': ApiErrorCode.duplicateExportNumber,
        'counter_not_initialized': ApiErrorCode.counterNotInitialized,
        'too_many_attempts': ApiErrorCode.tooManyAttempts,
      };

      for (final entry in cases.entries) {
        final failure = await failureFor(
          statusCode: 422,
          body: '{"message":"رسالة","error":"${entry.key}"}',
        );
        expect(failure.code, entry.value, reason: entry.key);
      }
    });

    test('an unrecognised code falls back to unknown rather than throwing',
        () async {
      final failure = await failureFor(
        statusCode: 418,
        body: '{"message":"x","error":"something_new_the_backend_added"}',
      );
      expect(failure.code, ApiErrorCode.unknown);
      expect(failure.message, 'x');
    });

    test('the backend message is preferred over the built-in Arabic default',
        () async {
      // These messages are written for the end user and pinned to the code,
      // so the exact backend wording is what the UI should show.
      const arabic = 'رقم الصادر 42 مستخدم مسبقاً في هذا القسم.';
      final failure = await failureFor(
        statusCode: 422,
        body: '{"message":"$arabic","error":"duplicate_export_number"}',
      );
      expect(
        arabicMessageFor(failure.code, fallback: failure.message),
        arabic,
      );
      // …and there is still a sensible default when no message came back.
      expect(
        arabicMessageFor(ApiErrorCode.duplicateExportNumber),
        isNotEmpty,
      );
    });
  });

  group('ApiFailure retains the whole envelope', () {
    test('status, error code, field errors and retry_after all survive',
        () async {
      final failure = await failureFor(
        statusCode: 429,
        body: '{"message":"انتظر","error":"too_many_attempts",'
            '"retry_after":60,"errors":{"email":["غير صحيحة"]}}',
      );

      expect(failure.statusCode, 429);
      expect(failure.code, ApiErrorCode.tooManyAttempts);
      expect(failure.message, 'انتظر');
      expect(failure.retryAfter, 60);
      expect(failure.firstErrorFor('email'), 'غير صحيحة');
    });

    test('retry_after falls back to the Retry-After header', () async {
      // The framework's own throttle:api limiter sends only the header.
      final failure = await failureFor(
        statusCode: 429,
        body: '{"message":"Too Many Attempts.","error":"http_error"}',
        headers: {
          'retry-after': ['45'],
        },
      );
      expect(failure.retryAfter, 45);
    });

    test('retry_after is null when neither body nor header carries one',
        () async {
      final failure = await failureFor(
        statusCode: 422,
        body: '{"message":"x","error":"validation_failed"}',
      );
      expect(failure.retryAfter, isNull);
    });
  });

  group('array-field validation errors', () {
    test('errorsForPrefix collects every indexed approver_ids error', () {
      final failure = ApiFailure(
        code: ApiErrorCode.validationFailed,
        message: 'invalid',
        fieldErrors: {
          'approver_ids.0': [
            'المعتمد المحدد غير موجود أو ليس مديراً أو رئيساً.'
          ],
          'approver_ids.2': [
            'المعتمد المحدد غير موجود أو ليس مديراً أو رئيساً.'
          ],
          'title': ['مطلوب'],
        },
      );

      expect(failure.errorsForPrefix('approver_ids'), hasLength(2));
      // A same-prefixed but different field must not be swept in.
      expect(failure.errorsForPrefix('title'), hasLength(1));
      expect(failure.invalidIndicesFor('approver_ids'), {0, 2});
    });

    test('a bare approver_ids error names no index', () {
      final failure = ApiFailure(
        code: ApiErrorCode.validationFailed,
        message: 'invalid',
        fieldErrors: {
          'approver_ids': ['مطلوب'],
        },
      );

      expect(failure.errorsForPrefix('approver_ids'), ['مطلوب']);
      expect(failure.invalidIndicesFor('approver_ids'), isEmpty);
    });

    test('prefix matching does not confuse a longer sibling field name', () {
      final failure = ApiFailure(
        code: ApiErrorCode.validationFailed,
        message: 'invalid',
        fieldErrors: {
          'approver_ids_extra': ['nope'],
        },
      );
      expect(failure.errorsForPrefix('approver_ids'), isEmpty);
    });
  });

  group('authentication', () {
    test('the bearer token is attached to outgoing requests', () async {
      final adapter = _CannedAdapter(statusCode: 200, body: '{}');
      final client = ApiClient(
        tokenStorage: _FakeTokenStorage('secret-token'),
        onUnauthenticated: () {},
      );
      client.dio.httpClientAdapter = adapter;

      await client.dio.get<Map<String, dynamic>>('/me');

      expect(
        adapter.lastRequest!.headers['Authorization'],
        'Bearer secret-token',
      );
    });

    test('a 401 clears the session and signals the router', () async {
      final storage = _FakeTokenStorage('stale-token');
      var signalled = false;
      final adapter = _CannedAdapter(
        statusCode: 401,
        body: '{"message":"Unauthenticated.","error":"unauthenticated"}',
      );
      final client = ApiClient(
        tokenStorage: storage,
        onUnauthenticated: () => signalled = true,
      );
      client.dio.httpClientAdapter = adapter;

      await expectLater(
        client.dio.get<Map<String, dynamic>>('/documents'),
        throwsA(isA<DioException>()),
      );

      expect(storage.clearCount, 1);
      expect(signalled, isTrue);
    });
  });
}
