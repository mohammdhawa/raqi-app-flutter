import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/about/about_screen.dart';
import '../../features/account/presentation/account_screen.dart';
import '../../features/attendance/presentation/screens/attendance_history_screen.dart';
import '../../features/attendance/presentation/screens/attendance_screen.dart';
import '../../features/attendance/presentation/screens/attendance_tab_screen.dart';
import '../../features/attendance/presentation/screens/leave_request_detail_screen.dart';
import '../../features/attendance/presentation/screens/leave_request_form_screen.dart';
import '../../features/auth/domain/user.dart';
import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/documents/presentation/screens/create_document_screen.dart';
import '../../features/documents/presentation/screens/document_details_screen.dart';
import '../../features/documents/presentation/screens/documents_home_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/notifications/domain/notification_model.dart';
import '../../features/notifications/presentation/screens/broadcast_notification_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/requests/presentation/screens/requests_screen.dart';
import '../../features/salary/presentation/salary_screen.dart';
import '../../features/splash/splash_screen.dart';
import 'app_shell.dart';

/// The root navigator. Detail screens are pushed on it rather than inside a
/// tab, so they cover the tab bar — a push notification lands on the document
/// or request it is about, not on a tab with a detail squeezed into it.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// The five tab roots, in tab order: الرئيسية, دوامي, الطلبات, راتبي, حسابي.
///
/// A provider so tests can swap the real screens — each of which loads its
/// own data — for stubs and exercise the route tree alone. Each builder runs
/// inside its tab's page, so it can read that page's [GoRouterState].
final tabScreensProvider = Provider<List<WidgetBuilder>>((ref) {
  return [
    (_) => const HomeScreen(),
    (_) => const AttendanceTabScreen(),
    (context) => RequestsScreen(
          openInbox:
              GoRouterState.of(context).uri.queryParameters['seg'] == 'inbox',
        ),
    (_) => const SalaryScreen(),
    (_) => const AccountScreen(),
  ];
});

/// Where the router sends [matchedLocation] for the given [auth] state, or
/// `null` to stay. Pure so the access rules are testable without a router.
String? resolveRedirect({
  required AuthState auth,
  required String matchedLocation,
}) {
  final onSplash = matchedLocation == '/splash';
  final loggingIn = matchedLocation == '/login';

  // While on splash, let SplashScreen handle its own navigation.
  if (onSplash) return null;

  // Wait for the bootstrap to finish before redirecting anywhere.
  if (auth is AuthInitial) return '/splash';

  final isAuthenticated = auth is AuthAuthenticated;
  if (!isAuthenticated && !loggingIn) return '/login';
  if (isAuthenticated && loggingIn) return '/';

  // A missing/unknown role is a no-capabilities state, never an implicit
  // manager. Keep document routes out of reach until `/me` returns a known
  // document-workflow role; the backend remains the final authorization.
  final onDocumentRoute = matchedLocation.startsWith('/documents');
  if (auth is AuthAuthenticated &&
      onDocumentRoute &&
      !auth.user.canUseDocumentWorkflow) {
    return '/';
  }

  // The old leave hub is now the requests tab. Only the exact path forwards:
  // `leave/new` and `leave/requests/:id` are still live deep-link targets.
  if (matchedLocation == '/attendance/leave') return '/requests?seg=inbox';
  return null;
}

/// App router. Uses a small [Listenable] adapter so go_router rebuilds when
/// the auth state changes (login / logout / forced-logout via 401).
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref);
  final tabs = ref.read(tabScreensProvider);

  // A tab root, built inside its own page so the builder sees that page's
  // route state.
  GoRouterWidgetBuilder tab(int index) =>
      (_, __) => Builder(builder: tabs[index]);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) => resolveRedirect(
      auth: ref.read(authControllerProvider),
      matchedLocation: state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/',
              builder: tab(0),
              routes: [
                GoRoute(
                  path: 'documents/new',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (_, __) => const CreateDocumentScreen(),
                ),
                GoRoute(
                  path: 'documents/:id',
                  parentNavigatorKey: rootNavigatorKey,
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
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (_, __) => const NotificationsScreen(),
                  routes: [
                    GoRoute(
                      path: 'broadcast/:id',
                      parentNavigatorKey: rootNavigatorKey,
                      builder: (context, state) {
                        final id = state.pathParameters['id'] ?? '';
                        if (id.isEmpty) return const _NotFoundScreen();
                        // When opened from the in-app list, the notification
                        // comes through as `extra` so its content renders
                        // immediately.
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
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (_, __) => const AboutScreen(),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/attendance',
              builder: tab(1),
              routes: [
                GoRoute(
                  path: 'history',
                  parentNavigatorKey: rootNavigatorKey,
                  // `?date=YYYY-MM-DD` opens the listing on a single day —
                  // how an `attendance_rejected` notification for an earlier
                  // date lands on the day it is about. A malformed value is
                  // ignored rather than failing the route: the unfiltered
                  // history is still the right screen.
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
                  parentNavigatorKey: rootNavigatorKey,
                  // Never built: resolveRedirect forwards the old leave hub to
                  // the requests inbox. The route stays so its children keep
                  // their paths.
                  builder: (_, __) => const SizedBox.shrink(),
                  routes: [
                    GoRoute(
                      path: 'new',
                      parentNavigatorKey: rootNavigatorKey,
                      builder: (_, __) => const LeaveRequestFormScreen(),
                    ),
                    GoRoute(
                      path: 'requests/:id',
                      parentNavigatorKey: rootNavigatorKey,
                      builder: (context, state) {
                        final id =
                            int.tryParse(state.pathParameters['id'] ?? '');
                        if (id == null) return const _NotFoundScreen();
                        return LeaveRequestDetailScreen(leaveRequestId: id);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/requests', builder: tab(2)),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/salary', builder: tab(3)),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/account', builder: tab(4)),
          ]),
        ],
      ),
    ],
    errorBuilder: (_, __) => const _NotFoundScreen(),
  );
});

/// The pre-shell landing decision: a known document role got the documents
/// home, everyone else attendance. `/` now renders the shell's Home tab; this
/// stays only while the role-less fail-closed test still pins it.
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
