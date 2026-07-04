import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/services/push_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/attendance/presentation/providers/attendance_sync_service.dart';
import 'features/auth/presentation/providers/auth_controller.dart';
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

class _DocApprovalAppState extends ConsumerState<DocApprovalApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupNotifications();
    _setupAttendanceSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(attendanceSyncServiceProvider).syncPending();
    }
  }

  /// Pushes any attendance records queued offline on a previous run, then
  /// keeps listening so reconnecting triggers a retry automatically.
  ///
  /// Session restoration is async, so `currentUserProvider` is still null
  /// here — wait for auth to resolve (covers app startup) and re-run on
  /// every future login too, so a previous run's queue isn't stranded.
  void _setupAttendanceSync() {
    final syncService = ref.read(attendanceSyncServiceProvider);
    syncService.listenForConnectivity();
    ref.listenManual(authControllerProvider, (previous, next) {
      if (next is AuthAuthenticated) syncService.syncPending();
    });
  }

  Future<void> _setupNotifications() async {
    final pushService = ref.read(pushNotificationServiceProvider);
    await pushService.init();

    pushService.listenForTokenRefresh();

    // Foreground: show a local banner
    FirebaseMessaging.onMessage.listen((message) {
      pushService.showLocalNotification(message);
    });

    // Foreground banner tap: navigate using the carried data map.
    pushService.onNotificationTap.listen(_navigateFromNotification);

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
    final router = ref.read(routerProvider);

    // Checkout reminder ("type": "attendance_checkout_reminder") opens the
    // check-in/out screen so the user can record the انصراف they forgot.
    if (data['type'] == 'attendance_checkout_reminder') {
      router.push('/attendance');
      return;
    }

    // A leave_request_id takes precedence so leave notifications open the
    // relevant request.
    final leaveRequestId = _asId(data['leave_request_id']);
    if (leaveRequestId != null) {
      router.push('/attendance/leave/requests/$leaveRequestId');
      return;
    }

    final documentId = _asId(data['document_id']);
    if (documentId != null) {
      router.push('/documents/$documentId');
    }
  }

  /// Notification payloads stringify ids; accept int / num / String.
  int? _asId(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
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
