import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

// Define this top-level function outside the class
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if needed
  // await Firebase.initializeApp();
  
  // Create notification channel for background notifications
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'blood_requests',
    'Blood Donation Requests',
    description: 'Notifications for urgent blood donation requests',
    importance: Importance.high,
  );
  
  // Initialize local notifications plugin
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  // Create notification channel
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
  
  // Show notification with actions
  final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'blood_requests',
    'Blood Donation Requests',
    channelDescription: 'Notifications for urgent blood donation requests',
    importance: Importance.high,
    priority: Priority.high,
    actions: <AndroidNotificationAction>[
      AndroidNotificationAction(
        'accept',
        'Accept',
        showsUserInterface: true,
      ),
      AndroidNotificationAction(
        'reject',
        'Reject',
        cancelNotification: true,
      ),
    ],
  );
  
  final NotificationDetails platformDetails = NotificationDetails(
    android: androidDetails,
  );
  
  // Convert message data to string for payload
  final String payload = message.data.entries
      .map((e) => "${e.key}:${e.value}")
      .join(",");
  
  // Show the notification
  await flutterLocalNotificationsPlugin.show(
    message.hashCode,
    message.notification?.title,
    message.notification?.body,
    platformDetails,
    payload: payload,
  );
  
  print("Handling background message: ${message.messageId}");
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = 
      FlutterLocalNotificationsPlugin();
  
  // Use GlobalKey<NavigatorState> instead of BuildContext
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  // Initialize notification channels and settings
  Future<void> initialize(BuildContext context) async {
    // Request permission
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    
    // Set up local notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
        
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    
    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationAction(response);
      },
    );
    
    // Create high priority channel for blood requests
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'blood_requests',
      'Blood Donation Requests',
      description: 'Notifications for urgent blood donation requests',
      importance: Importance.high,
    );
    
    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    
    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    
    // Handle when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleForegroundMessage(message);
    });
    
    // Handle when app is opened from terminated state
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        _navigateToDetailsPage(message.data, context);
      }
    });
    
    // Handle when app is in background but not terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _navigateToDetailsPage(message.data, context);
    });
  }
  
  // Handle notification actions (Accept or Reject)
  void _handleNotificationAction(NotificationResponse response) {
    final String? actionId = response.actionId;
    final String? payload = response.payload;
    
    if (payload != null) {
      // Convert payload string back to Map
      Map<String, dynamic> data = _parsePayload(payload);
      
      // If action is 'accept', navigate to details page
      if (actionId == 'accept') {
        _navigateToDetailsPage(data, navigatorKey.currentContext!);
      }
      // If action is 'reject', do nothing (notification will be dismissed)
      else if (actionId == null) {
        // If clicked on notification body (no specific action), also navigate
        _navigateToDetailsPage(data, navigatorKey.currentContext!);
      }
    }
  }
  
  // Handle messages that arrive when app is in foreground
  void _handleForegroundMessage(RemoteMessage message) async {
    print("Received message: ${message.messageId}");
    print("Message data: ${message.data}");
    
    if (message.notification != null) {
      // Check if notification has actions flag
      final bool hasActions = message.data['hasActions'] == 'true';
      
      print("Processing notification with hasActions: $hasActions");
      print("Notification title: ${message.notification?.title}");
      print("Notification body: ${message.notification?.body}");
      
      if (hasActions) {
        print("Showing notification with action buttons");
        // Show local notification with actions
        await _showLocalNotificationWithActions(message);
      } else {  
        print("Showing regular notification without buttons");
        // Show regular notification
        await _showLocalNotification(message);
      }
    }
  }
  
  // Show local notification with Accept and Reject buttons
  Future<void> _showLocalNotificationWithActions(RemoteMessage message) async {
    print("Setting up notification with actions");
    
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'blood_requests',
      'Blood Donation Requests',
      channelDescription: 'Notifications for urgent blood donation requests',
      importance: Importance.high,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'accept',
          'Accept',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'reject',
          'Reject',
          cancelNotification: true,
        ),
      ],
    );
    
    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );
    
    // Convert message data to string for payload
    final String payload = _convertDataToPayload(message.data);
    print("Prepared notification payload: $payload");
    
    try {
      await _flutterLocalNotificationsPlugin.show(
        message.hashCode,
        message.notification?.title,
        message.notification?.body,
        platformDetails,
        payload: payload,
      );
      print("Successfully showed notification with buttons");
    } catch (e) {
      print("Error showing notification: $e");
    }
  }
  
  // Show regular notification without actions
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'blood_requests',
      'Blood Donation Requests',
      channelDescription: 'Notifications for urgent blood donation requests',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );
    
    // Include payload even for regular notifications
    final String payload = _convertDataToPayload(message.data);
    
    await _flutterLocalNotificationsPlugin.show(
      message.hashCode,
      message.notification?.title,
      message.notification?.body,
      platformDetails,
      payload: payload,
    );
  }
  
  // Navigate to blood request details page using GlobalKey<NavigatorState>
  void _navigateToDetailsPage(Map<String, dynamic> data, BuildContext context) {
    final String screen = data['screen'] ?? '/bloodRequestDetails';
    // Remove leading slash if present
    final String routeName = screen.startsWith('/') ? screen : '/$screen';
    Navigator.of(context, rootNavigator: true).pushNamed(
      routeName,
      arguments: data,
    );
  }
  
  // Helper methods to convert between payload string and Map
  String _convertDataToPayload(Map<String, dynamic> data) {
    return data.entries.map((e) => "${e.key}:${e.value}").join(",");
  }
  
  Map<String, dynamic> _parsePayload(String payload) {
    final entries = payload.split(",");
    final Map<String, dynamic> result = {};
    for (var entry in entries) {
      final parts = entry.split(":");
      if (parts.length == 2) {
        result[parts[0]] = parts[1];
      }
    }
    return result;
  }
  
  // Get FCM token for this device (useful for testing)
  Future<String?> getToken() async {
    return await _firebaseMessaging.getToken();
  }
}