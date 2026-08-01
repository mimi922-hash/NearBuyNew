import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';
import 'splash_screen.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import 'customer_dashboard.dart';
import 'shopkeeper_dashboard.dart';
import 'admin_dashboard.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  print("===== Background Notification =====");
  print("Title : ${message.notification?.title}");
  print("Body  : ${message.notification?.body}");
}

Future<void> initializeFCM() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Notification Permission
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );

  print("Permission Status: ${settings.authorizationStatus}");

  // Device Token
  String? token = await messaging.getToken();

  print("==================================");
  print("FCM TOKEN:");
  print(token);
  print("==================================");

  // Foreground Notification
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print("===== Foreground Notification =====");
    print("Title : ${message.notification?.title}");
    print("Body  : ${message.notification?.body}");
  });

  // Notification Click
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print("Notification Clicked");
  });

  // App opened from terminated state
  RemoteMessage? initialMessage =
      await FirebaseMessaging.instance.getInitialMessage();

  if (initialMessage != null) {
    print("App opened from terminated state");
  }

  // Token Refresh
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    print("New Token: $newToken");
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(
    firebaseMessagingBackgroundHandler,
  );

  await initializeFCM();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NearBuy App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(role: 'Customer'),
        '/customerDashboard': (context) => const CustomerDashboard(),
        '/shopkeeperDashboard': (context) => const ShopkeeperDashboard(),
        '/adminDashboard': (context) => const AdminDashboard(),
      },
    );
  }
}