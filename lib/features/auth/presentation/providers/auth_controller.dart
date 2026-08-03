import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../data/auth_repository.dart';
import '../../domain/user.dart';
import '../../../../core/services/push_notification_service.dart';


/// Three possible auth states.
sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);
  final User user;
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// Holds the current session. The router watches this to decide between
/// /login and /home.
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repo, this._unauthenticatedSignal, this._pushService)
    : super(const AuthInitial()) {
    _unauthenticatedSignal.addListener(_onForcedLogout);
    _bootstrap();
  }

  final AuthRepository _repo;
  final UnauthenticatedSignal _unauthenticatedSignal;
  final PushNotificationService _pushService;

  static const _bootstrapTimeout = Duration(seconds: 10);

  /// Resolves the stored session on start-up.
  ///
  /// This *must* always land on a terminal state: the splash screen and the
  /// router both block on leaving [AuthInitial], so anything that escapes here
  /// leaves the app spinning on the splash forever. Restoring can genuinely
  /// fail (e.g. Android secure storage becoming undecryptable after an app
  /// update), so treat any failure as "no session" and send the user to login.
  Future<void> _bootstrap() async {
    User? user;
    try {
      // Reading secure storage is local and takes milliseconds; the timeout is
      // purely a deadlock guard so a wedged platform channel can't hold the
      // splash screen open indefinitely.
      user = await _repo.restoreSession().timeout(_bootstrapTimeout);
    } catch (e, st) {
      debugPrint('Session restore failed, falling back to login: $e\n$st');
      user = null;
    }

    if (user == null) {
      state = const AuthUnauthenticated();
      return;
    }

    state = AuthAuthenticated(user);

    // Re-register the FCM token on session restore (it may have rotated).
    // Deliberately not awaited as part of resolving auth — it hits Play
    // Services and the network, neither of which should gate the splash.
    _startPushSession();
  }

  /// Opens the push session in the background.
  ///
  /// Nothing here waits for it, and nothing needs to: ordering against a
  /// later logout is enforced inside the push service, which invalidates
  /// stale registrations and queues its requests, rather than by holding a
  /// future here and hoping it finishes first.
  void _startPushSession() {
    unawaited(_openPushSession());
  }

  /// Best-effort push registration; never allowed to surface as an error.
  Future<void> _openPushSession() async {
    try {
      await _pushService.beginSession();
    } catch (e) {
      debugPrint('FCM session registration failed: $e');
    }
  }

  Future<void> login(String email, String password) async {
    final result = await _repo.login(email: email, password: password);
    state = AuthAuthenticated(result.user);
    // Register the FCM token after login — off the critical path so a slow or
    // unavailable Play Services can't stall (or fail) an otherwise good login.
    _startPushSession();
  }

  Future<void> logout() async {
    // Closes the push session before anything else: it invalidates any
    // registration still in flight and sends the DELETE behind requests
    // already issued, so this device cannot end up re-registered to the
    // account we are signing out of.
    await _pushService.endSession();
    await _repo.logout();
    state = const AuthUnauthenticated();
  }

  void _onForcedLogout() {
    // Triggered by the API client on a 401 — token is already cleared.
    // Invalidate rather than end the push session: stale registrations and
    // token refreshes still have to be stopped, but we have no credentials
    // left to authorise a DELETE, and attempting one from here would 401 and
    // re-enter this very method. See PushNotificationService.invalidateSession.
    _pushService.invalidateSession();
    state = const AuthUnauthenticated();
  }

  @override
  void dispose() {
    _unauthenticatedSignal.removeListener(_onForcedLogout);
    super.dispose();
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
      return AuthController(
        ref.watch(authRepositoryProvider),
        ref.watch(unauthenticatedSignalProvider),
        ref.watch(pushNotificationServiceProvider),  // add this
      );
    });

/// Convenience accessor for the current user (null if not signed in).
final currentUserProvider = Provider<User?>((ref) {
  final state = ref.watch(authControllerProvider);
  return state is AuthAuthenticated ? state.user : null;
});