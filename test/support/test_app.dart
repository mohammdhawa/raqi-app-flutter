import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Pumps [home] at `/` inside a Riverpod scope and an RTL Arabic
/// `MaterialApp.router`. Any other location renders `route:<uri>` so tests can
/// assert where a tap navigated without building the real screens.
///
/// The app theme is intentionally not applied, matching the existing tests.
Future<void> pumpTestApp(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
}) async {
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, __) => home)],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('route:${state.uri}')),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
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
  await tester.pumpAndSettle();
}
