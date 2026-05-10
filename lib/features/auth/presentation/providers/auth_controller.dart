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

  Future<void> _bootstrap() async {
    final user = await _repo.restoreSession();
    if (user != null) {
      state = AuthAuthenticated(user);
      // Re-register FCM token on session restore (token may have rotated)
      await _pushService.registerToken();
      _pushService.listenForTokenRefresh();
    } else {
      state = const AuthUnauthenticated();
    }
  }

  Future<void> login(String email, String password) async {
    final result = await _repo.login(email: email, password: password);
    state = AuthAuthenticated(result.user);
    // Register FCM token after login
    await _pushService.registerToken();
    _pushService.listenForTokenRefresh();
  }

  Future<void> logout() async {
    // Remove FCM token before logout
    await _pushService.removeToken();
    await _repo.logout();
    state = const AuthUnauthenticated();
  }

  void _onForcedLogout() {
    // Triggered by the API client on a 401 — token is already cleared.
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