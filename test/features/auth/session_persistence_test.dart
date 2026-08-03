import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:doc_approval/core/network/api_client.dart';
import 'package:doc_approval/core/services/push_notification_service.dart';
import 'package:doc_approval/core/storage/token_storage.dart';
import 'package:doc_approval/core/utils/app_constants.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the plugin, with a switch to make chosen writes fail
/// the way a poisoned Android store does.
class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> store = {};

  /// Keys whose *next* write throws; the write after that succeeds. Mirrors
  /// the real failure, which clears once the store has been wiped.
  final Set<String> failWriteOnce = {};

  int wipeCount = 0;

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failWriteOnce.remove(key)) {
      throw PlatformException(
        code: 'Exception encountered',
        message: 'write',
        details: 'javax.crypto.BadPaddingException: pad block corrupted',
      );
    }
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      store[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    wipeCount++;
    store.clear();
  }
}

/// Records requests in completion order, and can hold one open on demand.
class _RecordingAdapter implements HttpClientAdapter {
  final List<String> completed = [];
  final Map<String, Completer<void>> gates = {};

  Completer<void> gate(String label) => gates[label] = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final label = '${options.method} ${options.path}';
    await gates[label]?.future;
    completed.add(label);
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeApiClient extends Fake implements ApiClient {
  _FakeApiClient(this.adapter) {
    _dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..httpClientAdapter = adapter;
  }

  final _RecordingAdapter adapter;
  late final Dio _dio;

  @override
  Dio get dio => _dio;
}

void main() {
  group('TokenStorage.writeSession', () {
    test('keeps the token when recovering from a failed profile write', () async {
      final fake = _FakeSecureStorage();
      // Token lands; profile trips the poisoned store. Recovery wipes, which
      // destroys the token that had already succeeded.
      fake.failWriteOnce.add(AppConstants.userKey);

      await TokenStorage(fake).writeSession(token: 'tok', userJson: '{"id":1}');

      expect(fake.wipeCount, 1, reason: 'recovery should wipe once');
      expect(
        fake.store[AppConstants.tokenKey],
        'tok',
        reason: 'the wipe erased the token, so the retry must rewrite it too',
      );
      expect(fake.store[AppConstants.userKey], '{"id":1}');
    });

    test('leaves nothing behind when the session cannot be written', () async {
      // Fails on every attempt, not just the first.
      final alwaysFails = _AlwaysFailingUserKey();

      await expectLater(
        TokenStorage(alwaysFails).writeSession(token: 'tok', userJson: '{}'),
        throwsA(isA<TokenStorageException>()),
      );
      expect(
        alwaysFails.store,
        isEmpty,
        reason: 'a lone token would authenticate an unrestorable session',
      );
    });
  });

  group('PushNotificationService session ordering', () {
    late _RecordingAdapter adapter;
    late _FakeApiClient api;

    setUp(() {
      adapter = _RecordingAdapter();
      api = _FakeApiClient(adapter);
    });

    test('logout DELETE is sent after an in-flight registration POST', () async {
      final service = PushNotificationService(
        api,
        fcmTokenSource: () async => 'fcm-token',
        tokenRefreshStream: const Stream<String>.empty(),
      );
      final postGate = adapter.gate('POST /device-tokens');

      final session = service.beginSession();
      // Let the POST reach the adapter and block there.
      await Future<void>.delayed(Duration.zero);

      final logout = service.endSession();
      postGate.complete();
      await Future.wait([session, logout]);

      expect(
        adapter.completed,
        ['POST /device-tokens', 'DELETE /device-tokens'],
        reason: 'the DELETE must not overtake a POST already in flight',
      );
    });

    test('a registration still fetching its token is dropped after logout', () async {
      final tokenGate = Completer<String?>();
      final service = PushNotificationService(
        api,
        fcmTokenSource: () => tokenGate.future,
        tokenRefreshStream: const Stream<String>.empty(),
      );

      final session = service.beginSession();
      // Logout while the Firebase phase is still outstanding.
      await service.endSession();
      tokenGate.complete('fcm-token');
      await session;

      expect(
        adapter.completed,
        ['DELETE /device-tokens'],
        reason: 'a stale generation must not re-register the device',
      );
    });

    test('a forced logout invalidates without sending anything', () async {
      final tokenGate = Completer<String?>();
      final service = PushNotificationService(
        api,
        fcmTokenSource: () => tokenGate.future,
        tokenRefreshStream: const Stream<String>.empty(),
      );

      final session = service.beginSession();
      // What a 401 does: the token is already gone, so no request can be made.
      service.invalidateSession();
      tokenGate.complete('fcm-token');
      await session;
      await Future<void>.delayed(Duration.zero);

      expect(
        adapter.completed,
        isEmpty,
        reason: 'an unauthenticated DELETE would 401, re-trigger the forced '
            'logout that sent it, and loop — while still dropping the stale '
            'registration, which is the part that must happen',
      );
    });

    test('token refreshes stop POSTing once the session ends', () async {
      final refreshes = StreamController<String>.broadcast();
      addTearDown(refreshes.close);
      final service = PushNotificationService(
        api,
        fcmTokenSource: () async => 'fcm-token',
        tokenRefreshStream: refreshes.stream,
      );

      await service.beginSession();
      refreshes.add('rotated-while-signed-in');
      await Future<void>.delayed(Duration.zero);

      await service.endSession();
      refreshes.add('rotated-after-logout');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        adapter.completed,
        [
          'POST /device-tokens', // initial registration
          'POST /device-tokens', // refresh during the session
          'DELETE /device-tokens',
        ],
        reason: 'the refresh listener outlives the session, so it must be '
            'gated on one being active — nothing may follow the DELETE',
      );
    });
  });
}

/// Rejects every write to the user key, however many times it is retried.
class _AlwaysFailingUserKey extends _FakeSecureStorage {
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (key == AppConstants.userKey) {
      throw PlatformException(code: 'Exception encountered', message: 'write');
    }
    return super.write(key: key, value: value);
  }
}
