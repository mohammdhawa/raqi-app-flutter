import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/app_constants.dart';

/// Thrown when a value could not be persisted even after wiping the store and
/// retrying.
///
/// Callers must treat the session as unsaveable rather than carrying on:
/// nothing would survive the next launch, and the API client re-reads the
/// token from storage on every request, so a dropped write becomes a stream of
/// 401s instead of one visible error.
class TokenStorageException implements Exception {
  const TokenStorageException(this.message);

  final String message;

  @override
  String toString() => 'TokenStorageException: $message';
}

/// Thin wrapper around [FlutterSecureStorage] for the auth token.
///
/// Uses Keychain on iOS and EncryptedSharedPreferences on Android,
/// matching the security requirement called out in the API docs.
class TokenStorage {
  TokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  /// What the Android plugin hands back in place of a value when
  /// `resetOnError` fires: it answers `result.success("Data has been reset")`
  /// for whichever call threw, and nothing between there and here filters it
  /// out — `read` is typed `String?` all the way down. Returned verbatim it
  /// would be used as a bearer token.
  static const _resetSentinel = 'Data has been reset';

  Future<String?> read() => _readOrReset(AppConstants.tokenKey);

  Future<void> clear() async {
    try {
      await _storage.delete(key: AppConstants.tokenKey);
      await _storage.delete(key: AppConstants.userKey);
    } on PlatformException catch (e) {
      // Deleting does not decrypt anything, so it will not hit the padding
      // failures reads do — but it still calls through to the platform and can
      // fail there. Wiping the whole store is the last resort so we never
      // leave a poisoned entry behind.
      debugPrint('Secure storage delete failed: $e');
      await _wipe();
    }
  }

  Future<String?> readUserJson() => _readOrReset(AppConstants.userKey);

  /// Persists a whole session — token *and* user profile — or nothing.
  ///
  /// The two keys are one unit, not two independent values: the API client
  /// attaches the token to every request, while `restoreSession()` needs the
  /// profile to rebuild the user. A store holding one without the other is a
  /// broken session, not a partial one.
  ///
  /// Recovery is what makes that sharp. Wiping to clear a poisoned store also
  /// destroys any key already written, so the retry has to rewrite *both*
  /// keys — retrying only the one that failed would leave the other one wiped
  /// and the caller none the wiser. Either both keys are written and verified,
  /// or the store is emptied (best effort) and [TokenStorageException] is
  /// thrown.
  Future<void> writeSession({
    required String token,
    required String userJson,
  }) async {
    if (await _trySession(token, userJson)) return;

    // Clear whatever undecryptable state the first attempt tripped over, then
    // rewrite the session from scratch. A retry without the wipe would hit the
    // same failure.
    await _wipe();
    if (await _trySession(token, userJson)) return;

    // Never leave a fragment behind: a lone token authenticates requests for a
    // user the next launch cannot reconstruct.
    await _wipe();
    throw const TokenStorageException(
      'Secure storage rejected the session write twice, including once on a '
      'freshly wiped store.',
    );
  }

  /// Writes and verifies both halves of the session. Never throws; `false`
  /// means the store does not hold a complete session.
  Future<bool> _trySession(String token, String userJson) async {
    if (!await _tryWrite(AppConstants.tokenKey, token)) return false;
    return _tryWrite(AppConstants.userKey, userJson);
  }

  /// Reads a key, degrading to "no session" instead of throwing.
  ///
  /// On Android the EncryptedSharedPreferences master key can go out of sync
  /// with the stored ciphertext after an app update, a reinstall, or a restore
  /// from auto-backup — the read then throws a [PlatformException] wrapping
  /// `BadPaddingException`/`InvalidKeyException`. Left uncaught this stranded
  /// the app on the splash screen forever.
  ///
  /// Only that corruption clears the store: it is permanent, so keeping the
  /// data would fail identically on every subsequent launch. Every other
  /// failure (a platform channel not ready yet, a transient plugin error) is
  /// reported as "no session" for this launch **without** deleting anything,
  /// so a later launch can still restore it. `_bootstrap()` catches the null
  /// and routes to login either way.
  Future<String?> _readOrReset(String key) async {
    try {
      final value = await _storage.read(key: key);
      // The plugin reset the store underneath us (see [_resetSentinel]); there
      // is no value to return and nothing left to clean up.
      if (value == _resetSentinel) {
        debugPrint('Secure storage reset itself while reading "$key"');
        return null;
      }
      return value;
    } catch (e) {
      final corrupt = _isCorruptionError(e);
      debugPrint(
        'Secure storage read failed for "$key" '
        '(${corrupt ? "corrupt — clearing" : "transient — keeping data"}): $e',
      );
      if (corrupt) await _wipe();
      return null;
    }
  }

  /// One write plus read-back. Never throws; `false` means "did not stick".
  ///
  /// Writes fail the same way reads do, and the plugin makes it sticky: once
  /// its EncryptedSharedPreferences init fails it latches onto the legacy
  /// cipher path for the rest of the process, so every later write throws too.
  /// A dropped write is worse than a dropped read — the session would look
  /// fine until the next launch, and every request in between re-reads a token
  /// that was never stored.
  ///
  /// Verification reads the value back. That proves the plugin round-trips it,
  /// not that it reached disk — `SharedPreferences.apply()` flushes
  /// asynchronously and updates its in-memory map first — but the cipher and
  /// channel failures worth catching here all surface on the read-back.
  Future<bool> _tryWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      final readBack = await _storage.read(key: key);
      if (readBack == value) return true;
      debugPrint(
        'Secure storage write for "$key" did not read back '
        '(got ${readBack == null ? "null" : "a different value"})',
      );
      return false;
    } catch (e) {
      debugPrint('Secure storage write failed for "$key": $e');
      return false;
    }
  }

  /// True when the payload can never be decrypted again, so retaining it is
  /// pointless. Matches the Android Keystore/Tink failures surfaced through
  /// the plugin; anything else is assumed recoverable.
  ///
  /// Kept deliberately narrow. Some corruption arrives as a bare
  /// `NullPointerException` (the plugin only logs a failed cipher init, then
  /// dereferences the null cipher), but matching on that would also catch
  /// every unrelated plugin bug and delete a perfectly good session. Those
  /// cases are covered one layer down instead, by `resetOnError` — see
  /// [tokenStorageProvider].
  static bool _isCorruptionError(Object error) {
    if (error is! PlatformException) return false;

    final haystack = [
      error.code,
      error.message ?? '',
      error.details?.toString() ?? '',
    ].join(' ').toLowerCase();

    const markers = [
      'badpadding', // javax.crypto.BadPaddingException
      'aeadbadtag', // AEADBadTagException — tampered/undecryptable blob
      'invalidkey', // InvalidKeyException — master key mismatch
      'illegalblocksize', // IllegalBlockSizeException
      'general security', // GeneralSecurityException
      'generalsecurity',
      'could not decrypt',
      'decryption failed',
      'keystore', // KeyStoreException / key no longer in the keystore
      'invalid protocol buffer', // corrupt Tink keyset
    ];

    return markers.any(haystack.contains);
  }

  Future<void> _wipe() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      debugPrint('Secure storage wipe failed: $e');
    }
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      // Safety net under the Dart-side handling: the plugin catches the
      // failure on the platform side and resets the store itself. It covers
      // what [TokenStorage._isCorruptionError] deliberately does not classify,
      // and — unlike anything we can do from Dart — it applies to `write` too.
      // Reads that trip it come back as [TokenStorage._resetSentinel].
      resetOnError: true,
    ),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  return TokenStorage(storage);
});
