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
  })  : _tokenStorage = tokenStorage,
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
        validateStatus: (s) => s != null && s <= 599,
      ),
    );

    // Auth + error-mapping interceptor.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStorage.read();
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
          // Non-2xx — convert to a typed failure and reject.
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

    // Logging (debug builds only, and deliberately metadata-only).
    //
    // Dio's LogInterceptor used to sit here with `requestHeader` and
    // `requestBody` on, which wrote the `Authorization: Bearer …` header of
    // every call and the full body of `POST /login` — password included — to
    // the device log, where any app holding READ_LOGS on older Androids and
    // anyone with the device attached to `adb`/Xcode can read them. Method,
    // path and status are enough to debug a request; the parts that identify
    // or authenticate the user are not logged at all rather than being
    // masked, so there is nothing to leak if the mask is ever wrong.
    if (kDebugMode) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            debugPrint('→ ${options.method} ${options.path}');
            handler.next(options);
          },
          onResponse: (response, handler) {
            debugPrint(
              '← ${response.statusCode} ${response.requestOptions.path}',
            );
            handler.next(response);
          },
          onError: (error, handler) {
            final failure = error.error;
            final code =
                failure is ApiFailure ? failure.code.name : error.type.name;
            debugPrint(
              '✖ ${error.response?.statusCode ?? '-'} '
              '${error.requestOptions.path} ($code)',
            );
            handler.next(error);
          },
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

    final ApiErrorCode resolvedCode = ApiErrorCode.fromString(errorCode);

    return ApiFailure(
      code: resolvedCode,
      message: message,
      statusCode: response.statusCode,
      fieldErrors: fieldErrors,
      retryAfter: _retryAfterFrom(response),
    );
  }

  /// Seconds still to wait, for a throttled (429) response.
  ///
  /// The login throttle sends `retry_after` in the body and mirrors it in the
  /// standard `Retry-After` header; the framework's own `throttle:api` limiter
  /// sends only the header. Reading both means a client that trips either one
  /// gets a usable countdown.
  int? _retryAfterFrom(Response response) {
    final data = response.data;
    if (data is Map) {
      final raw = data['retry_after'];
      final parsed =
          raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
      if (parsed != null && parsed >= 0) return parsed;
    }
    final header = response.headers.value('retry-after');
    final parsed = int.tryParse(header ?? '');
    return (parsed != null && parsed >= 0) ? parsed : null;
  }

  ApiFailure _failureFromException(DioException e) {
    final isNetwork = e.type == DioExceptionType.connectionTimeout ||
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

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  final signal = ref.watch(unauthenticatedSignalProvider);
  return ApiClient(
    tokenStorage: storage,
    onUnauthenticated: signal.fire,
  );
});
