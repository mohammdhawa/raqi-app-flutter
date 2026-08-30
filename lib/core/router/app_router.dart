import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/about/about_screen.dart';
import '../../features/attendance/presentation/screens/attendance_history_screen.dart';
import '../../features/attendance/presentation/screens/attendance_screen.dart';
import '../../features/attendance/presentation/screens/leave_request_detail_screen.dart';
import '../../features/attendance/presentation/screens/leave_request_form_screen.dart';
import '../../features/attendance/presentation/screens/leave_screen.dart';
import '../../features/auth/domain/user.dart';
import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/documents/presentation/screens/create_document_screen.dart';
import '../../features/documents/presentation/screens/document_details_screen.dart';
import '../../features/documents/presentation/screens/documents_home_screen.dart';
import '../../features/notifications/domain/notification_model.dart';
import '../../features/notifications/presentation/screens/broadcast_notification_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/splash/splash_screen.dart';

/// App router. Uses a small [Listenable] adapter so go_router rebuilds when
/// the auth state changes (login / logout / forced-logout via 401).
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final onSplash = state.matchedLocation == '/splash';
      final loggingIn = state.matchedLocation == '/login';

      // While on splash, let SplashScreen handle its own navigation.
      if (onSplash) return null;

      // Wait for the bootstrap to finish before redirecting anywhere.
      if (authState is AuthInitial) return '/splash';

      final isAuthenticated = authState is AuthAuthenticated;
      if (!isAuthenticated && !loggingIn) return '/login';
      if (isAuthenticated && loggingIn) return '/';

      // A missing/unknown role is a no-capabilities state, never an implicit
      // manager. Keep document routes out of reach until `/me` returns a known
      // document-workflow role; the backend remains the final authorization.
      final onDocumentRoute = state.matchedLocation.startsWith('/documents');
      if (authState is AuthAuthenticated &&
          onDocumentRoute &&
          !authState.user.canUseDocumentWorkflow) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (_, __) => const _HomeScreen(),
        routes: [
          GoRoute(
            path: 'documents/new',
            builder: (_, __) => const CreateDocumentScreen(),
          ),
          GoRoute(
            path: 'documents/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) {
                return const _NotFoundScreen();
              }
              return DocumentDetailsScreen(documentId: id);
            },
          ),
          GoRoute(
            path: 'notifications',
            builder: (_, __) => const NotificationsScreen(),
            routes: [
              GoRoute(
                path: 'broadcast/:id',
                builder: (context, state) {
                  final id = state.pathParameters['id'] ?? '';
                  if (id.isEmpty) return const _NotFoundScreen();
                  // When opened from the in-app list, the notification comes
                  // through as `extra` so its content renders immediately.
                  final extra = state.extra;
                  return BroadcastNotificationScreen(
                    broadcastId: id,
                    initial: extra is AppNotification ? extra : null,
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: 'about',
            builder: (_, __) => const AboutScreen(),
          ),
          GoRoute(
            path: 'attendance',
            builder: (_, __) => const AttendanceScreen(),
            routes: [
              GoRoute(
                path: 'history',
                // `?date=YYYY-MM-DD` opens the listing on a single day — how
                // an `attendance_rejected` notification for an earlier date
                // lands on the day it is about. A malformed value is ignored
                // rather than failing the route: the unfiltered history is
                // still the right screen.
                builder: (context, state) {
                  final raw = state.uri.queryParameters['date'];
                  final parsed = raw == null ? null : DateTime.tryParse(raw);
                  return AttendanceHistoryScreen(
                    initialDate: parsed == null
                        ? null
                        : DateTime(parsed.year, parsed.month, parsed.day),
                  );
                },
              ),
              GoRoute(
                path: 'leave',
                builder: (context, state) {
                  // Optional `{ 'tab': 1 }` extra selects the approvals tab.
                  final extra = state.extra;
                  final tab = extra is Map && extra['tab'] is int
                      ? extra['tab'] as int
                      : 0;
                  return LeaveScreen(initialTab: tab);
                },
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (_, __) => const LeaveRequestFormScreen(),
                  ),
                  GoRoute(
                    path: 'requests/:id',
                    builder: (context, state) {
                      final id = int.tryParse(state.pathParameters['id'] ?? '');
                      if (id == null) return const _NotFoundScreen();
                      return LeaveRequestDetailScreen(leaveRequestId: id);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (_, __) => const _NotFoundScreen(),
  );
});

/// Picks the landing screen from positive role capabilities. A missing or
/// unknown role gets only the employee-level attendance surface.
class _HomeScreen extends ConsumerWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return homeScreenForUser(user);
  }
}

/// Pure landing decision kept public so fail-closed behavior is testable.
Widget homeScreenForUser(User? user) {
  if (user?.canUseDocumentWorkflow == true) {
    return const DocumentsHomeScreen();
  }

  return const AttendanceScreen();
}

class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(Ref ref) {
    _sub = ref.listen<AuthState>(authControllerProvider, (_, __) {
      notifyListeners();
    });
  }

  late final ProviderSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 64),
              const SizedBox(height: 12),
              const Text('الصفحة غير موجودة.'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => GoRouter.of(context).go('/'),
                child: const Text('العودة للرئيسية'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
