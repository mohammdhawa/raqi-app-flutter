import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/services/push_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart'; // ← NEW

/// Top-level background handler (must be a top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(
    const ProviderScope(
      child: DocApprovalApp(),
    ),
  );
}

class DocApprovalApp extends ConsumerStatefulWidget {
  const DocApprovalApp({super.key});

  @override
  ConsumerState<DocApprovalApp> createState() => _DocApprovalAppState();
}

class _DocApprovalAppState extends ConsumerState<DocApprovalApp> {
  @override
  void initState() {
    super.initState();
    _setupNotifications();
  }

  Future<void> _setupNotifications() async {
    final pushService = ref.read(pushNotificationServiceProvider);
    await pushService.init();

    pushService.listenForTokenRefresh();

    // Foreground: show a local banner
    FirebaseMessaging.onMessage.listen((message) {
      pushService.showLocalNotification(message);
    });

    // Background tap: navigate to document
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _navigateFromNotification(message.data);
    });

    // App was terminated — check if opened via notification
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _navigateFromNotification(initialMessage.data);
    }
  }

  void _navigateFromNotification(Map<String, dynamic> data) {
    final documentId = data['document_id'];
    if (documentId != null) {
      final router = ref.read(routerProvider);
      router.push('/documents/$documentId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'سير اعتماد المستندات',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}