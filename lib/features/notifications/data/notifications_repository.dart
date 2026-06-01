import 'package:dio/dio.dart' show DioException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_failure.dart';
import '../../../core/network/api_client.dart';
import '../domain/notification_model.dart';

/// Wraps every notification-related endpoint.
/// Returns parsed domain objects; throws [ApiFailure] on errors
/// (mapped by the [ApiClient] interceptor).
class NotificationsRepository {
  NotificationsRepository(this._api);

  final ApiClient _api;

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      if (e.error is ApiFailure) throw e.error as ApiFailure;
      rethrow;
    }
  }

  /// `GET /notifications?page=N`
  Future<NotificationsPage> list({int page = 1}) async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
      '/notifications',
      queryParameters: {'page': page},
    ));
    return NotificationsPage.fromJson(response.data!);
  }

  /// `GET /notifications/unread-count`
  Future<int> unreadCount() async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
      '/notifications/unread-count',
    ));
    return (response.data!['unread_count'] as int?) ?? 0;
  }

  /// `POST /notifications/{id}/read`
  Future<void> markAsRead(int id) async {
    await _run(() => _api.dio.post<Map<String, dynamic>>(
      '/notifications/$id/read',
    ));
  }

  /// `POST /notifications/read-all`
  Future<void> markAllAsRead() async {
    await _run(() => _api.dio.post<Map<String, dynamic>>(
      '/notifications/read-all',
    ));
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);