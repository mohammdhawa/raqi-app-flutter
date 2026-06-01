import 'package:dio/dio.dart' show DioException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_failure.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/user.dart';

/// Fetches managers to populate the approver picker on the
/// "create document" screen via the `/managers` endpoint.
class UsersRepository {
  UsersRepository(this._api);

  final ApiClient _api;

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      if (e.error is ApiFailure) throw e.error as ApiFailure;
      rethrow;
    }
  }

  Future<List<User>> searchPotentialApprovers({String? search}) async {
    final response = await _run(() => _api.dio.get<Map<String, dynamic>>(
      '/managers',
      queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        'per_page': 50,
      },
    ));
    final data = response.data!;
    final paginator = data['managers'] as Map<String, dynamic>?;
    if (paginator == null) return [];
    final list = (paginator['data'] as List?) ?? [];
    return list
        .map((e) => User.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(ref.watch(apiClientProvider));
});