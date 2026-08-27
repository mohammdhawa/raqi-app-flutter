import 'package:doc_approval/core/network/api_client.dart';
import 'package:doc_approval/core/services/push_notification_service.dart';
import 'package:doc_approval/core/services/session_cleanup.dart';
import 'package:doc_approval/features/auth/data/auth_repository.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the session wipe is actually TRIGGERED.
///
/// The bug these cover shipped twice: the wipe itself was written and even
/// unit-tested, but it hung off a listener registered in the root widget's
/// initState, and nothing anywhere asserted that signing out ran it. On the
/// device it did not, and the only symptom was cached document images still
/// sitting in the cache directory after logout — invisible from the UI,
/// because the app happily re-downloads them.
///
/// So these tests deliberately do not check what a wipe deletes (that is
/// media_cache_test.dart). They check that logging out runs one.
class _FakeAuthRepository extends Fake implements AuthRepository {
  _FakeAuthRepository({this.restored});

  final User? restored;
  bool loggedOut = false;

  @override
  Future<User?> restoreSession() async => restored;

  @override
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async =>
      AuthResult(user: const User(id: 2, name: 'الثاني'), token: 'tok');

  @override
  Future<void> logout({bool logoutFromAll = false}) async {
    loggedOut = true;
  }
}

class _FakePushService extends Fake implements PushNotificationService {
  @override
  Future<void> beginSession() async {}

  @override
  Future<void> endSession() async {}

  @override
  void invalidateSession() {}
}

/// Counts runs instead of touching a real cache.
class _SpyCleanup implements SessionCleanup {
  int runs = 0;

  @override
  Future<void> run() async => runs++;
}

void main() {
  late _SpyCleanup cleanup;
  late UnauthenticatedSignal signal;

  setUp(() {
    cleanup = _SpyCleanup();
    signal = UnauthenticatedSignal();
  });

  AuthController controllerFor(_FakeAuthRepository repo) {
    final controller =
        AuthController(repo, signal, _FakePushService(), cleanup);
    addTearDown(controller.dispose);
    return controller;
  }

  test('signing out wipes the session caches', () async {
    final controller = controllerFor(
      _FakeAuthRepository(restored: const User(id: 1, name: 'الأول')),
    );
    await Future<void>.delayed(Duration.zero); // let the bootstrap settle
    expect(cleanup.runs, 0, reason: 'a restored session must not wipe');

    await controller.logout();

    expect(cleanup.runs, 1);
    expect(controller.state, isA<AuthUnauthenticated>());
  });

  // The wipe must land before the app is showing the login screen, so it
  // cannot be left half-done by whatever happens next.
  test('the wipe completes before the state flips to signed out', () async {
    final controller = controllerFor(
      _FakeAuthRepository(restored: const User(id: 1, name: 'الأول')),
    );
    await Future<void>.delayed(Duration.zero);

    var runsWhenUnauthenticated = -1;
    controller.addListener((state) {
      if (state is AuthUnauthenticated) runsWhenUnauthenticated = cleanup.runs;
    }, fireImmediately: false);

    await controller.logout();

    expect(runsWhenUnauthenticated, 1);
  });

  // A 401 revokes the session from the server side. It ends just as
  // definitively as a tapped logout, and used to be the easier path to miss.
  test('a forced 401 logout wipes them too', () async {
    controllerFor(
      _FakeAuthRepository(restored: const User(id: 1, name: 'الأول')),
    );
    await Future<void>.delayed(Duration.zero);

    signal.fire();
    await Future<void>.delayed(Duration.zero);

    expect(cleanup.runs, 1);
  });

  // Covers the session that ended when the process was killed: logout never
  // ran, so whatever it cached is still there when the next person signs in.
  test('signing in wipes what a previous session left behind', () async {
    final controller = controllerFor(_FakeAuthRepository());
    await Future<void>.delayed(Duration.zero);
    expect(cleanup.runs, 0);

    await controller.login('a@example.com', 'secret');

    expect(cleanup.runs, 1);
    expect(controller.state, isA<AuthAuthenticated>());
  });

  // Restoring is the SAME account that filled the cache. Wiping there would
  // empty it on every cold start and protect nobody.
  test('restoring a session on start-up does not wipe', () async {
    controllerFor(
      _FakeAuthRepository(restored: const User(id: 1, name: 'الأول')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(cleanup.runs, 0);
  });

  test('one failing wipe does not stop the others or the logout', () async {
    var second = 0;
    final cleanup = SessionCleanup([
      () async => throw const FormatException('store unavailable'),
      () async => second++,
    ]);

    await expectLater(cleanup.run(), completes);
    expect(second, 1);
  });
}
