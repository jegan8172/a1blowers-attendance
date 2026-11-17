import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'auth_storage.dart';
import 'chat_api.dart';
import 'chat_navigation.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await PushNotifications.ensureFirebaseInitialized();
}

class PushNotifications {
  PushNotifications._();
  static final instance = PushNotifications._();
  static bool _firebaseAvailable = false;
  bool _listenersAttached = false;
  GlobalKey<NavigatorState>? _navigatorKey;

  static String get _webApiKey => const String.fromEnvironment('FIREBASE_WEB_API_KEY');
  static String get _webAppId => const String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static FirebaseOptions? get _webOptions {
    if (_webApiKey.isEmpty || _webAppId.isEmpty) return null;
    return FirebaseOptions(
      apiKey: _webApiKey,
      appId: _webAppId,
      messagingSenderId: const String.fromEnvironment('FIREBASE_WEB_MESSAGING_SENDER_ID'),
      projectId: const String.fromEnvironment('FIREBASE_WEB_PROJECT_ID'),
      authDomain: const String.fromEnvironment('FIREBASE_WEB_AUTH_DOMAIN'),
      storageBucket: const String.fromEnvironment('FIREBASE_WEB_STORAGE_BUCKET'),
      measurementId: const String.fromEnvironment('FIREBASE_WEB_MEASUREMENT_ID'),
    );
  }

  static Future<bool> ensureFirebaseInitialized() async {
    if (_firebaseAvailable) return true;
    try {
      if (Firebase.apps.isEmpty) {
        final options = kIsWeb ? _webOptions : null;
        if (kIsWeb && options == null) {
          debugPrint('Firebase push disabled: missing Firebase web build configuration.');
          return false;
        }
        await Firebase.initializeApp(options: options);
      }
      _firebaseAvailable = true;
    } catch (error) {
      debugPrint('Firebase push disabled: $error');
      _firebaseAvailable = false;
    }
    return _firebaseAvailable;
  }

  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;
    if (!await ensureFirebaseInitialized()) return;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    if (!_listenersAttached) {
      _listenersAttached = true;
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);
      FirebaseMessaging.onMessageOpenedApp.listen(_openConversation);
      FirebaseMessaging.instance.onTokenRefresh.listen((token) => _registerToken(token));
    }
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) _openConversation(initialMessage);
    if (kIsWeb) {
      final raw = Uri.base.queryParameters['conversationId'];
      _openConversationId(int.tryParse(raw ?? ''));
    }
  }

  Future<void> registerDevice() async {
    if (!await ensureFirebaseInitialized()) return;
    try {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? const String.fromEnvironment('FIREBASE_WEB_VAPID_KEY') : null,
      );
      if (token != null && token.isNotEmpty) await _registerToken(token);
    } catch (error) {
      debugPrint('Chat push token registration skipped: $error');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      final platform = kIsWeb
          ? 'web'
          : defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      await ChatApi.registerPushToken(token, platform);
    } catch (error) {
      // Token registration is best-effort and must not affect sign-in.
      debugPrint('Chat push token registration failed: $error');
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    final title = message.notification?.title ?? 'GoDigital Attendance';
    final body = message.notification?.body ?? 'You have a new update.';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('$title: $body'), action: SnackBarAction(label: 'Open', onPressed: () => _openConversation(message))),
    );
  }

  void _openConversation(RemoteMessage message) => _openConversationId(int.tryParse(message.data['conversationId'] ?? ''));

  Future<void> _openConversationId(int? conversationId) async {
    if (conversationId == null || conversationId <= 0) return;
    ChatNavigation.openConversation(conversationId);
    final raw = await AuthStorage.getString('user_data');
    String userType = '';
    try { userType = (jsonDecode(raw ?? '{}') as Map)['userType']?.toString().toLowerCase() ?? ''; } catch (_) {}
    final route = userType == 'admin' ? '/admin/chat' : '/employee/chat';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKey?.currentState?.pushNamedAndRemoveUntil(route, (route) => false);
    });
  }
}
