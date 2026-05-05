import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/token_storage.dart';
import '../domain/user.dart';

/// Result of a successful login: the user + the bearer token.
class AuthResult {
  AuthResult({required this.user, required this.token});
  final User user;
  final String token;
}

/// Talks to the auth endpoints. The exact login endpoint isn't in the
/// provided documentation ("auth endpoints assumed to already exist"), so
/// we follow the standard Sanctum-issuing convention: POST /login with
/// email + password, returning `{ user, token }`. Adjust if your backend
/// uses a different shape.
class AuthRepository {
  AuthRepository(this._api, this._storage);

  final ApiClient _api;
  final TokenStorage _storage;

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/login',
      data: {'email': email, 'password': password},
    );
    final data = response.data!;
    final token = data['token'] as String;
    final user = User.fromJson(data['user'] as Map<String, dynamic>);

    await _storage.write(token);

    await _storage.writeUserJson(jsonEncode(user.toJson()));
    return AuthResult(user: user, token: token);
  }

  Future<void> logout() async {
    // Best-effort: hit the backend, but always clear local state.
    try {
      await _api.dio.post('/logout');
    } catch (_) {
      // Ignore — token might already be invalid; we still clear locally.
    }
    await _storage.clear();
  }

  /// Restore a previously-saved session on app start.
  Future<User?> restoreSession() async {
    final token = await _storage.read();
    if (token == null || token.isEmpty) return null;
    final userJson = await _storage.readUserJson();
    if (userJson == null) return null;
    try {
      return User.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
    } catch (_) {
      await _storage.clear();
      return null;
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
  );
});
