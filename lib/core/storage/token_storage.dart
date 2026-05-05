import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/app_constants.dart';

/// Thin wrapper around [FlutterSecureStorage] for the auth token.
///
/// Uses Keychain on iOS and EncryptedSharedPreferences on Android,
/// matching the security requirement called out in the API docs.
class TokenStorage {
  TokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  Future<String?> read() => _storage.read(key: AppConstants.tokenKey);

  Future<void> write(String token) =>
      _storage.write(key: AppConstants.tokenKey, value: token);

  Future<void> clear() async {
    await _storage.delete(key: AppConstants.tokenKey);
    await _storage.delete(key: AppConstants.userKey);
  }

  Future<String?> readUserJson() => _storage.read(key: AppConstants.userKey);

  Future<void> writeUserJson(String json) =>
      _storage.write(key: AppConstants.userKey, value: json);
}

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  return TokenStorage(storage);
});
