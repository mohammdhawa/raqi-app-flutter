import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';

/// Handles FCM setup, token registration, and incoming notification display.
class PushNotificationService {
  PushNotificationService(this._api);

  final ApiClient _api;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  
  /// Called once after Firebase.initializeApp()
  Future<void> init() async {
    // Request permission (iOS + Android 13+)
    await FirebaseMessaging.instance.requestPermission();

    // Setup local notifications for foreground banners
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Create Android notification channel
    const channel = AndroidNotificationChannel(
      'raqi_approvals',
      'إشعارات الاعتمادات',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Register FCM token with the backend (call after login)
  Future<void> registerToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    debugPrint('FCM token: $token');
    try {
      await _api.dio.post('/device-tokens', data: {'token': token});
    } catch (e) {
      debugPrint('Failed to register FCM token: $e');
    }
  }

  /// Remove FCM token from backend (call before logout)
  Future<void> removeToken() async {
    try {
      await _api.dio.delete('/device-tokens');
    } catch (_) {}
  }

  /// Listen for token refreshes and re-register
  void listenForTokenRefresh() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      try {
        await _api.dio.post('/device-tokens', data: {'token': newToken});
      } catch (_) {}
    });
  }

  /// Show a local notification banner when the app is in the foreground
  void showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'raqi_approvals',
          'إشعارات الاعتمادات',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref.watch(apiClientProvider));
});