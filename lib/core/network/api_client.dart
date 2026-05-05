import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/api_failure.dart';
import '../storage/token_storage.dart';
import '../utils/app_constants.dart';
import 'package:flutter/foundation.dart';

/// Callback the auth layer wires up to handle global 401s.
typedef OnUnauthenticated = void Function();

/// Creates and configures the app's [Dio] instance.
///
/// Two interceptors:
///   1. Auth — attaches `Authorization: Bearer {token}` to every request,
///      and on 401 clears storage + invokes [onUnauthenticated] so the
///      router can bounce to login.
///   2. Error mapping — converts every [DioException] into a typed
///      [ApiFailure] with one of the documented error codes.
class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    required OnUnauthenticated onUnauthenticated,
  }) : _tokenStorage = tokenStorage,
      _onUnauthenticated = onUnauthenticated {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: AppConstants.connectTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        headers: {
          'Accept': 'application/json',
          // Remove 'Content-Type': 'application/json'
          // Dio sets it automatically — multipart needs its own boundary
        },
        validateStatus: (s) => s != null && s < 500,
      ),
    );

    // Auth + error-mapping interceptor.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStorage.read();
          debugPrint(
            'REQUEST ${options.method} ${options.path} - token: '
            '${token == null ? "NULL" : "present (${token.length} chars)"}',
          );
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          final status = response.statusCode ?? 0;
          if (status >= 200 && status < 300) {
            handler.next(response);
            return;
          }
          // 4xx — convert to a typed failure and reject.
          final failure = _failureFromResponse(response);
          if (failure.code == ApiErrorCode.unauthenticated) {
            await _tokenStorage.clear();
            _onUnauthenticated();
          }
          handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              error: failure,
              type: DioExceptionType.badResponse,
            ),
          );
        },
        onError: (error, handler) async {
          if (error.error is ApiFailure) {
            handler.next(error);
            return;
          }
          handler.next(error.copyWith(error: _failureFromException(error)));
        },
      ),
    );

    // Logging (debug only).
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestHeader: true,
          requestBody: true,
          responseHeader: false,
          responseBody: true,
          error: true,
          logPrint: (obj) => debugPrint(obj.toString()),
        ),
      );
    }
  }

  late final Dio _dio;
  final TokenStorage _tokenStorage;
  final OnUnauthenticated _onUnauthenticated;

  Dio get dio => _dio;

  ApiFailure _failureFromResponse(Response response) {
    final data = response.data;
    String message = 'حدث خطأ.';
    String? errorCode;
    Map<String, List<String>>? fieldErrors;

    if (data is Map) {
      message = (data['message'] as String?) ?? message;
      errorCode = data['error'] as String?;
      final rawErrors = data['errors'];
      if (rawErrors is Map) {
        fieldErrors = rawErrors.map(
          (k, v) => MapEntry(
            k.toString(),
            (v as List).map((e) => e.toString()).toList(),
          ),
        );
      }
    }

    return ApiFailure(
      code: ApiErrorCode.fromString(errorCode),
      message: message,
      statusCode: response.statusCode,
      fieldErrors: fieldErrors,
    );
  }

  ApiFailure _failureFromException(DioException e) {
    final isNetwork =
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.error is SocketException;

    if (isNetwork) {
      return ApiFailure(
        code: ApiErrorCode.network,
        message: arabicMessageFor(ApiErrorCode.network),
      );
    }
    return ApiFailure(
      code: ApiErrorCode.unknown,
      message: e.message ?? arabicMessageFor(ApiErrorCode.unknown),
    );
  }
}

/// Provider holding a singleton [ApiClient].
///
/// The `onUnauthenticated` callback is wired to a notifier that the router
/// listens to — when invoked, the router redirects to /login. We use a
/// shared notifier instead of going through the auth provider directly to
/// avoid a circular dependency (auth depends on api, api would depend on
/// auth).
final unauthenticatedSignalProvider = Provider<UnauthenticatedSignal>(
  (ref) => UnauthenticatedSignal(),
);

class UnauthenticatedSignal {
  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
  void fire() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}

typedef VoidCallback = void Function();

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  final signal = ref.watch(unauthenticatedSignalProvider);
  return ApiClient(
    tokenStorage: storage,
    onUnauthenticated: signal.fire,
  );
});
