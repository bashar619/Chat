// lib/data/services/chat_notification.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:youtube_messenger_app/data/models/chat_message.dart';
import 'package:youtube_messenger_app/data/models/chat_room_model.dart';
import 'package:youtube_messenger_app/data/repositories/auth_repository.dart';
import 'package:youtube_messenger_app/data/services/service_locator.dart';
import 'package:youtube_messenger_app/router/app_router.dart';
import 'package:youtube_messenger_app/presentation/chat/chat_message_screen.dart';

class ChatNotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    await _setupFCM();
    await _setupLocalNotifications();
    _handleMessageInteractions();
  }

  Future<void> _setupFCM() async {
    // Request permissions
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get FCM token and save it for the current user
    final String? token = await _firebaseMessaging.getToken();
    if (token != null) {
      print('FCM token: $token');
      await _saveFCMToken(token);
    }

    // Listen for token refresh
    _firebaseMessaging.onTokenRefresh.listen(_saveFCMToken);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background/terminated messages
    FirebaseMessaging.onMessageOpenedApp.listen(_navigateToChat);
  }

  Future<void> _saveFCMToken(String token) async {
    final currentUser = getIt<AuthRepository>().currentUser;
    if (currentUser != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({
        'fcmTokens': FieldValue.arrayUnion([token])
      });
    }
  }

  Future<void> _setupLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        // when the user taps the notification
        _navigateToChatFromPayload(response.payload);
      },
    );
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'chat_channel', // id
      'Chat Messages', // user‐visible name
      description: 'Incoming messages',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    if (message.notification != null && message.data['chatRoomId'] != null) {
      _showLocalNotification(
        title: message.notification?.title,
        body: message.notification?.body,
        payload: message.data['chatRoomId'],
      );
    }
  }

  Future<void> _showLocalNotification({
    String? title,
    String? body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'chat_channel',
      'Chat Messages',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _localNotifications.show(
      0,
      title,
      body,
      details,
      payload: payload,
    );
  }

  void _handleMessageInteractions() {
    FirebaseMessaging.instance.getInitialMessage().then(_navigateToChat);
  }

  Future<void> _navigateToChat(RemoteMessage? message) async {
    final chatRoomId = message?.data['chatRoomId'];
    if (chatRoomId == null) return;

    // fetch the room to get participants & names
    final roomDoc = await FirebaseFirestore.instance
        .collection('chatRooms')
        .doc(chatRoomId)
        .get();
    if (!roomDoc.exists) return;

    final room = ChatRoomModel.fromFirestore(roomDoc);
    final currentUserId = getIt<AuthRepository>().currentUser!.uid;
    final otherId = room.participants.firstWhere((id) => id != currentUserId);
    final otherName = room.participantsName?[otherId] ?? '';

    getIt<AppRouter>().push(
      ChatMessageScreen(
        receiverId: otherId,
        receiverName: otherName,
      ),
    );
  }

  Future<void> _navigateToChatFromPayload(String? payload) async {
    if (payload == null) return;
    await _routeToChatScreen(payload);
  }

  /// Shared logic: load the room, pick the "other" user, and push screen
  Future<void> _routeToChatScreen(String chatRoomId) async {
    final roomDoc = await FirebaseFirestore.instance
        .collection('chatRooms')
        .doc(chatRoomId)
        .get();
    if (!roomDoc.exists) return;

    final room = ChatRoomModel.fromFirestore(roomDoc);
    final currentUserId = getIt<AuthRepository>().currentUser!.uid;
    final otherUserId =
        room.participants.firstWhere((id) => id != currentUserId);
    final otherUserName = room.participantsName?[otherUserId] ?? '';

    getIt<AppRouter>().push(
      ChatMessageScreen(
        receiverId: otherUserId,
        receiverName: otherUserName,
      ),
    );
  }

  // Call this when user logs out
  Future<void> deleteFCMToken() async {
    final currentUser = getIt<AuthRepository>().currentUser;
    final String? token = await _firebaseMessaging.getToken();
    if (currentUser != null && token != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({
        'fcmTokens': FieldValue.arrayRemove([token])
      });
    }
  }

  // Add app state awareness
  void _handleAppStateChanges() {
    AppLifecycleListener(
      onResume: () async {
        // Refresh token when app comes to foreground
        final token = await _firebaseMessaging.getToken();
        if (token != null) _saveFCMToken(token);
      },
    );
  }
}
