import 'package:dio/dio.dart';
import 'package:doc_approval/core/errors/api_failure.dart';
import 'package:doc_approval/core/network/api_client.dart';
import 'package:doc_approval/core/providers/app_info_provider.dart';
import 'package:doc_approval/core/router/app_router.dart';
import 'package:doc_approval/features/auth/domain/user.dart';
import 'package:doc_approval/features/auth/presentation/providers/auth_controller.dart';
import 'package:doc_approval/features/notifications/data/notifications_repository.dart';
import 'package:doc_approval/features/notifications/domain/notification_model.dart';
import 'package:doc_approval/features/requests/presentation/providers/requests_providers.dart';
import 'package:doc_approval/features/requests/presentation/screens/requests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const manager = User(id: 8, name: 'm', role: 'manager');
const roleless = User(id: 7, name: 'x');

/// A signed-in session that never touches the network or secure storage.
class _FakeAuth extends StateNotifier<AuthState> implements AuthController {
  _FakeAuth(User user) : super(AuthAuthenticated(user));

  @override
  Future<void> logout() async {}

  @override
  Future<void> login(String email, String password) async {}
}

/// Fails every request at once as offline, so detail screens opened by a deep
/// link render their own error state instead of reaching a real server.
class _OfflineApiClient extends Fake implements ApiClient {
  _OfflineApiClient() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: ApiFailure(code: ApiErrorCode.network, message: 'offline'),
          ),
        ),
      ),
    );
  }

  final Dio _dio = Dio();

  @override
  Dio get dio => _dio;
}

/// One unread checkout reminder; marking it read is a no-op.
class _OneReminderRepository extends Fake implements NotificationsRepository {
  @override
  Future<NotificationsPage> list({int page = 1}) async => NotificationsPage(
        notifications: [
          AppNotification(
            id: 1,
            title: 'reminder',
            body: 'checkout',
            type: NotificationType.attendanceCheckoutReminder,
            createdAt: DateTime(2026, 10, 18, 15),
          ),
        ],
        currentPage: 1,
        lastPage: 1,
        total: 1,
      );

  @override
  Future<void> markAsRead(int id) async {}
}

/// Builds the real router with the five tabs replaced by `Text` stubs, except
/// the requests tab when [requestsTab] is given.
Future<GoRouter> _pumpRouter(
  WidgetTester t, {
  int pendingDecisions = 0,
  WidgetBuilder? requestsTab,
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(overrides: [
    ...overrides,
    authControllerProvider.overrideWith((ref) => _FakeAuth(manager)),
    apiClientProvider.overrideWithValue(_OfflineApiClient()),
    appVersionProvider.overrideWithValue('2.0.0'),
    pendingDecisionsCountProvider.overrideWithValue(pendingDecisions),
    tabScreensProvider.overrideWithValue([
      for (final name in [
        'home',
        'attendance',
        'requests',
        'salary',
        'account'
      ])
        if (name == 'requests' && requestsTab != null)
          requestsTab
        else
          (_) => Text('tab:$name'),
    ]),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
  // Let the splash screen's minimum display run out, as on a real launch: it
  // then sends the signed-in session to `/`, and leaves no timer pending.
  await t.pump(const Duration(seconds: 2));
  await t.pumpAndSettle();
  return router;
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  test('unauthenticated goes to login', () {
    expect(
      resolveRedirect(
          auth: const AuthUnauthenticated(), matchedLocation: '/requests'),
      '/login',
    );
  });

  test('role-less user cannot open document routes', () {
    expect(
      resolveRedirect(
          auth: const AuthAuthenticated(roleless),
          matchedLocation: '/documents/9'),
      '/',
    );
  });

  test('old leave hub forwards to the requests inbox', () {
    expect(
      resolveRedirect(
          auth: const AuthAuthenticated(manager),
          matchedLocation: '/attendance/leave'),
      '/requests?seg=inbox',
    );
  });

  test('only the exact leave hub forwards; its children stay put', () {
    for (final loc in [
      '/attendance/leave/new',
      '/attendance/leave/requests/5'
    ]) {
      expect(
        resolveRedirect(
            auth: const AuthAuthenticated(manager), matchedLocation: loc),
        isNull,
        reason: loc,
      );
    }
  });

  testWidgets('legacy deep links resolve', (t) async {
    final router = await _pumpRouter(t);
    for (final loc in [
      '/attendance/leave/requests/5',
      '/attendance/history?date=2026-10-16',
      '/documents/9',
      '/notifications/broadcast/x',
    ]) {
      router.go(loc);
      await t.pumpAndSettle();
      expect(_location(router), loc);
      expect(find.byType(NavigationBar), findsNothing,
          reason: '$loc must cover the tab bar');
    }
  });

  // A tab root is reached with go, never push: pushing one from a detail
  // screen on the root navigator duplicates the shell's page key.
  testWidgets('a pushed detail can leave for a tab root', (t) async {
    final router = await _pumpRouter(t);
    router.push('/notifications');
    await t.pumpAndSettle();
    router.go('/attendance');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(_location(router), '/attendance');
    expect(find.text('tab:attendance'), findsOne);
    expect(find.byType(NavigationBar), findsOne);
  });

  testWidgets('a checkout reminder in the list opens the attendance tab',
      (t) async {
    final router = await _pumpRouter(t, overrides: [
      notificationsRepositoryProvider
          .overrideWithValue(_OneReminderRepository()),
    ]);
    router.push('/notifications');
    await t.pumpAndSettle();
    await t.tap(find.text('reminder'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(_location(router), '/attendance');
    expect(find.text('tab:attendance'), findsOne);
    expect(find.byType(NavigationBar), findsOne);
  });

  testWidgets('the old leave hub lands on the requests inbox', (t) async {
    final router = await _pumpRouter(t);
    router.go('/attendance/leave');
    await t.pumpAndSettle();
    expect(_location(router), '/requests?seg=inbox');
    expect(find.text('tab:requests'), findsOne);
  });

  testWidgets('seg=inbox opens the requests tab on the inbox', (t) async {
    final defaults = ProviderContainer();
    addTearDown(defaults.dispose);
    final router =
        await _pumpRouter(t, requestsTab: defaults.read(tabScreensProvider)[2]);

    bool opensInbox(Widget w) => w is RequestsScreen && w.openInbox;
    router.go('/requests?seg=inbox');
    await t.pumpAndSettle();
    expect(find.byWidgetPredicate(opensInbox), findsOne);

    router.go('/requests');
    await t.pumpAndSettle();
    expect(find.byType(RequestsScreen), findsOne);
    expect(find.byWidgetPredicate(opensInbox), findsNothing);
  });

  testWidgets('five tabs, badge on الطلبات', (t) async {
    final router = await _pumpRouter(t, pendingDecisions: 3);
    router.go('/');
    await t.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOne);
    expect(find.text('tab:home'), findsOne);
    for (final label in ['الرئيسية', 'دوامي', 'الطلبات', 'راتبي', 'حسابي']) {
      expect(find.text(label), findsOne, reason: label);
    }
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('3')),
      findsOne,
    );

    await t.tap(find.text('دوامي'));
    await t.pumpAndSettle();
    expect(_location(router), '/attendance');
    expect(find.text('tab:attendance'), findsOne);
  });

  testWidgets('no badge while nothing waits on me', (t) async {
    final router = await _pumpRouter(t);
    router.go('/');
    await t.pumpAndSettle();
    expect(find.byType(Badge), findsNothing);
  });
}
