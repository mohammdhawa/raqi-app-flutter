import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'core/providers/app_info_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/push_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/payload_ids.dart';
import 'features/attendance/presentation/providers/attendance_controller.dart';
import 'features/attendance/presentation/providers/attendance_sync_service.dart';
import 'features/attendance/presentation/providers/leave_providers.dart';
import 'features/auth/presentation/providers/auth_controller.dart';

/// Top-level background handler (must be a top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Read the version from the platform build (derived from pubspec.yaml) so the
  // splash/login/about captions stay in sync with a single source of truth.
  final packageInfo = await PackageInfo.fromPlatform();

  runApp(
    ProviderScope(
      overrides: [
        appVersionProvider.overrideWithValue(packageInfo.version),
      ],
      child: const DocApprovalApp(),
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
      // Refetch today's records on every resume. Two things can have changed
      // while the app was away, and only one of them is a date: the calendar
      // day may have rolled over (yesterday's check-in must not drive this
      // morning's status), and HR may have refused a record — which happens
      // on TODAY's date, so the controller's same-day guard would skip it and
      // leave the employee looking at a check-in the server no longer counts.
      // Hence reload() rather than refreshToday(): a small GET per resume is
      // the price of not showing a state the server has already moved past.
      // Guarded by exists() to avoid eagerly creating the controller (and
      // firing its API call) for users who never opened attendance.
      if (ref.exists(attendanceControllerProvider)) {
        ref.read(attendanceControllerProvider.notifier).reload();
      }
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
      if (next is AuthAuthenticated) {
        syncService.syncPending();
        // Reclaim selfie files orphaned by a mid-capture/mid-sync process
        // kill — best-effort, off the critical path.
        syncService.sweepOrphanedSelfies();
      }
    });
  }

  // Session cache cleanup used to live here, as a listener on the auth state.
  // It now lives in AuthController.logout() / login() / _onForcedLogout(),
  // because a listener registered in initState is a mechanism that can fail to
  // exist, and when it did the only symptom was protected document images
  // sitting in the cache directory after sign-out. See SessionCleanup.

  Future<void> _setupNotifications() async {
    final pushService = ref.read(pushNotificationServiceProvider);
    await pushService.init();

    pushService.listenForTokenRefresh();

    // Foreground: show a local banner, and act on payloads that change what
    // the user is allowed to do right now — without waiting for a tap.
    FirebaseMessaging.onMessage.listen((message) {
      pushService.showLocalNotification(message);
      _applyNotificationSideEffects(message.data);
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

  /// Applies what a payload changes in the app's own state, independently of
  /// where (or whether) it navigates.
  ///
  /// Runs on a foreground push AND on every tap: a refusal arriving while the
  /// user sits on the attendance screen has to take effect there and then, and
  /// a tap that lands on that screen must not show what was true before it.
  void _applyNotificationSideEffects(Map<String, dynamic> data) {
    final type = data['type'];

    // HR refused an attendance event. The server has stopped counting it, so
    // the day's check-in slot is free again — but only a refetch tells this
    // device that. Without it the refused check-in keeps driving status and
    // the app keeps offering «تسجيل انصراف» against a record the backend
    // cannot see, so every attempt 422s and the employee cannot do the one
    // thing the notification asked of them.
    //
    // Forced, because the refusal is about TODAY: the ordinary same-day guard
    // in refreshToday() would skip it.
    if (type == 'attendance_rejected') {
      if (ref.exists(attendanceControllerProvider)) {
        ref.read(attendanceControllerProvider.notifier).reload();
      }
      return;
    }

    // HR filed an excuse on the employee's behalf. The leave list gains a row
    // they never submitted, so refresh it either way — but only re-read the
    // balance when the excuse actually cost them days. `deducts_balance`
    // arrives as the string "1"/"0" (FCM data values always do); a
    // non-deducting excuse must not send the employee off to check a balance
    // that did not move.
    if (type == 'leave_excuse_recorded') {
      // exists() so this doesn't eagerly build the list controller (which
      // loads itself on creation) for a user who has never opened leave.
      if (ref.exists(myLeaveRequestsProvider)) {
        ref.read(myLeaveRequestsProvider.notifier).refresh();
      }
      if (data['deducts_balance']?.toString() == '1') {
        ref.invalidate(leaveBalanceProvider);
      }
    }
  }

  void _navigateFromNotification(Map<String, dynamic> data) {
    final router = ref.read(routerProvider);
    _applyNotificationSideEffects(data);

    // Checkout reminder ("type": "attendance_checkout_reminder") opens the
    // check-in/out screen so the user can record the انصراف they forgot.
    if (data['type'] == 'attendance_checkout_reminder') {
      router.push('/attendance');
      return;
    }

    // A refusal opens the day it is about: today's screen when it is today —
    // where the check-in button is now back — otherwise the history filtered
    // to that date, where the refused row and its reason are.
    if (data['type'] == 'attendance_rejected') {
      final date = _asDate(data['date']);
      final now = DateTime.now();
      final isToday = date != null &&
          date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
      if (date == null || isToday) {
        router.push('/attendance');
      } else {
        final ymd = '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
        router.push('/attendance/history?date=$ymd');
      }
      return;
    }

    // An admin broadcast ("type": "broadcast") opens the dedicated broadcast
    // page, which resolves the message from the list by its broadcast_id.
    if (data['type'] == 'broadcast') {
      final broadcastId = data['broadcast_id']?.toString();
      if (broadcastId != null && broadcastId.isNotEmpty) {
        router.push('/notifications/broadcast/$broadcastId');
      }
      return;
    }

    // A leave_request_id takes precedence so leave notifications open the
    // relevant request.
    final leaveRequestId = PushNotificationService.leaveRequestIdFrom(data);
    if (leaveRequestId != null) {
      router.push('/attendance/leave/requests/$leaveRequestId');
      return;
    }

    final documentId = payloadId(data['document_id']);
    if (documentId != null) {
      router.push('/documents/$documentId');
    }
  }

  /// A `Y-m-d` payload date, truncated to the calendar day. `null` when
  /// absent or unparseable — the caller then falls back to today's screen
  /// rather than routing nowhere.
  DateTime? _asDate(dynamic raw) {
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
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
