import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/documents/presentation/screens/create_document_screen.dart';
import '../../features/documents/presentation/screens/document_details_screen.dart';
import '../../features/documents/presentation/screens/documents_home_screen.dart';
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
        builder: (_, __) => const DocumentsHomeScreen(),
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
        ],
      ),
    ],
    errorBuilder: (_, __) => const _NotFoundScreen(),
  );
});

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