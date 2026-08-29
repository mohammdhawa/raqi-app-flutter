import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../utils/payload_ids.dart';

/// Handles FCM setup, token registration, and incoming notification display.
class PushNotificationService {
  /// [fcmTokenSource] and [tokenRefreshStream] exist so the session/ordering
  /// logic can be exercised without a live Firebase; both default to the real
  /// thing, so production behaviour is unchanged.
  PushNotificationService(
    this._api, {
    Future<String?> Function()? fcmTokenSource,
    Stream<String>? tokenRefreshStream,
  })  : _fcmTokenSource = fcmTokenSource ?? _firebaseTokenSource,
        _tokenRefreshStream = tokenRefreshStream;

  /// Rotates the FCM token and returns the new one.
  static Future<String?> _firebaseTokenSource() async {
    await FirebaseMessaging.instance.deleteToken();
    return FirebaseMessaging.instance.getToken();
  }

  final ApiClient _api;
  final Future<String?> Function() _fcmTokenSource;
  final Stream<String>? _tokenRefreshStream;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  Stream<String> get _refreshStream =>
      _tokenRefreshStream ?? FirebaseMessaging.instance.onTokenRefresh;

  StreamSubscription<String>? _tokenRefreshSub;

  /// Bumped whenever the signed-in session changes. Anything captured under an
  /// older generation is stale and must never reach the network — the account
  /// it would register this device against is gone.
  int _generation = 0;

  /// True only between [beginSession] and [endSession]. The refresh listener
  /// outlives any one session (it is installed at app start), so it needs this
  /// to know whether there is an account to register a token for at all.
  bool _sessionActive = false;

  /// Serialises every `/device-tokens` mutation.
  ///
  /// Ordering is the entire point: logout's DELETE must be *sent* after any
  /// POST already in flight. Waiting on the registration future with a timeout
  /// cannot do that — a timeout stops the waiting, not the request, so the
  /// POST it gave up on can still land after the DELETE. Chaining the requests
  /// makes the ordering a property of the queue instead of a race.
  Future<void> _deviceTokenQueue = Future<void>.value();

  final _notificationTapController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Extracts the route key shared by every leave push.
  ///
  /// In particular, `leave_request_approval_required` and
  /// `leave_request_approval_reassigned` add step metadata but retain the same
  /// `leave_request_id` contract as submitted/reviewed notifications. Routing
  /// by that stable key — not by an exhaustive type switch — also keeps future
  /// leave events deep-link compatible without another client release.
  static int? leaveRequestIdFrom(Map<String, dynamic> data) =>
      payloadId(data['leave_request_id']);

  /// Emits the notification's `data` map whenever the user taps a foreground
  /// notification banner — so callers can route on `document_id`,
  /// `leave_request_id`, etc.
  Stream<Map<String, dynamic>> get onNotificationTap =>
      _notificationTapController.stream;

  /// Called once after Firebase.initializeApp()
  Future<void> init() async {
    // Request permission (iOS + Android 13+)
    await FirebaseMessaging.instance.requestPermission();

    // Setup local notifications for foreground banners
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create Android notification channel
    const channel = AndroidNotificationChannel(
      'raqi_approvals',
      'إشعارات الاعتمادات',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Opens a push session for the freshly signed-in user and registers this
  /// device against it. Call after login and after restoring a session.
  ///
  /// Safe to call repeatedly: each call supersedes the previous session, so an
  /// earlier registration still in flight is marked stale and drops itself
  /// rather than registering this device to an account that has moved on.
  Future<void> beginSession() async {
    final generation = ++_generation;
    _sessionActive = true;
    listenForTokenRefresh();
    await _registerCurrentToken(generation);
  }

  /// Ends the push session without touching the network.
  ///
  /// For sessions ended *for* us — a 401 forced logout — where the token is
  /// already cleared by the time we hear about it. Sending the DELETE there
  /// would be actively harmful twice over:
  ///
  ///  * Unauthenticated, it comes back 401, which trips forced logout again,
  ///    which queues another DELETE — a loop with no exit, since the queue is
  ///    built to survive failing entries.
  ///  * It is queued, and the auth interceptor resolves the `Authorization`
  ///    header when the request finally runs, not when it is enqueued. A user
  ///    who signs in before the queue drains would have their *own*
  ///    registrations deleted by the previous session's DELETE.
  ///
  /// Invalidating alone is enough: the backend has already rejected the
  /// session, and the next [beginSession] re-registers this device.
  void invalidateSession() {
    _generation++;
    _sessionActive = false;
  }

  /// Closes the push session and unregisters this device. Call before an
  /// explicit logout, while credentials that can authorise the DELETE are
  /// still valid — for a forced one use [invalidateSession].
  ///
  /// Invalidates every in-flight registration first — so anything still
  /// working its way through Firebase drops itself instead of POSTing — then
  /// queues the DELETE behind requests already sent, so it cannot be
  /// overtaken by one of them.
  Future<void> endSession() async {
    invalidateSession();
    await _enqueue(() async {
      try {
        await _api.dio.delete('/device-tokens');
      } catch (_) {}
    });
  }

  /// Fetches a fresh FCM token and registers it under [generation].
  ///
  /// The Firebase calls sit deliberately *outside* the queue: they can take
  /// seconds, and holding the queue for them would let a slow Play Services
  /// delay a logout's DELETE. Staleness is handled by the generation check
  /// instead of by blocking.
  Future<void> _registerCurrentToken(int generation) async {
    final String? token;
    try {
      token = await _fcmTokenSource();
    } catch (e) {
      debugPrint('Could not obtain an FCM token: $e');
      return;
    }
    if (token == null) return;
    if (kDebugMode) debugPrint('FCM token: $token');
    await _postToken(token, generation);
  }

  /// Queues a token registration, dropping it if its session has ended.
  Future<void> _postToken(String token, int generation) {
    return _enqueue(() async {
      // Re-checked here, not just at the call site: an entry can sit in the
      // queue while the user logs out, and posting then would re-register a
      // device we have just told the backend to forget.
      if (generation != _generation || !_sessionActive) {
        debugPrint('Dropping stale FCM registration (generation $generation)');
        return;
      }
      try {
        await _api.dio.post('/device-tokens', data: {'token': token});
      } catch (e) {
        debugPrint('Failed to register FCM token: $e');
      }
    });
  }

  /// Appends [op] to the `/device-tokens` chain, completing when it has run.
  Future<void> _enqueue(Future<void> Function() op) {
    final queued = _deviceTokenQueue.then((_) => op());
    // The chain must survive a failing entry, or every later request would
    // inherit that error and never be sent.
    _deviceTokenQueue = queued.catchError((Object _) {});
    return queued;
  }

  /// Listen for token refreshes and re-register.
  ///
  /// Installed once at app start (`main.dart`) and again by every
  /// [beginSession]; the guard keeps it to a single subscription, since each
  /// extra one would re-POST the same token on every refresh.
  ///
  /// Because it outlives any individual session, a refresh is gated on a
  /// session being active and goes through the same queue as everything else —
  /// a refresh firing mid-logout must not overtake the DELETE either.
  void listenForTokenRefresh() {
    _tokenRefreshSub ??= _refreshStream.listen((newToken) {
      if (!_sessionActive) {
        debugPrint('Ignoring FCM token refresh: no active session');
        return;
      }
      unawaited(_postToken(newToken, _generation));
    });
  }

  /// Show a local notification banner when the app is in the foreground
  void showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    // Carry the whole data map so the tap handler can route on whichever
    // id it finds (document_id, leave_request_id, …).
    final payload = jsonEncode(message.data);

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
      payload: payload,
    );
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _notificationTapController.add(decoded.cast<String, dynamic>());
      }
    } on FormatException {
      // Legacy payloads were a bare document id string.
      final docId = int.tryParse(payload);
      if (docId != null) {
        _notificationTapController.add({'document_id': docId});
      }
    }
  }
}

final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref.watch(apiClientProvider));
});
