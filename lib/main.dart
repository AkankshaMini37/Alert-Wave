//import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lbp_app/firebase_options.dart';
//import 'package:firebase_database/firebase_database.dart';
import 'package:lbp_app/signup_page.dart';
import 'package:lbp_app/home_page.dart';
import 'package:lbp_app/firebase_api.dart';
//import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:lbp_app/notifications_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  // FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  // FirebaseDatabase.instance.useDatabaseEmulator('localhost', 9000);
  // Request permission and get the FCM token
  //FirebaseAnalytics analytics = FirebaseAnalytics.instance;
  await NotificationService.initialize();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await FirebaseApi().intiNotifications();
  await requestNotificationPermissions();
  runApp(const MyApp());
}

Future<void> requestNotificationPermissions() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Request permission to send notifications
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    print('User granted permission for notifications');

    // Get the FCM Token
    String? fcmToken = await messaging.getToken();
    print("FCM Token: $fcmToken");

    // Optionally, send the token to your server here or save it for later use
  } else {
    print('User denied permission');
  }
}

// Future<String?> _getFcmToken() async {
//   FirebaseMessaging messaging = FirebaseMessaging.instance;

//   // Check if the user has authorized notifications
//   NotificationSettings settings = await messaging.requestPermission();

//   if (settings.authorizationStatus == AuthorizationStatus.authorized) {
//     print('User granted permission');

//     // Get the FCM Token
//     String? token = await messaging.getToken();
//     return token;
//   } else {
//     // Handle cases where the user has denied notification permissions
//     print('User denied permission');
//     return null;
//   }
// }

Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background messages here
  print('Title: ${message.notification?.title}');
  print('Body: ${message.notification?.body}');
  print('Payload: ${message.data}');
  print('Handling a background message: ${message.messageId}');
  await NotificationService.showNotification(message);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alert Wave',
      theme: ThemeData(
        fontFamily: 'Cera Pro',
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          contentPadding: const EdgeInsets.all(27),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade300, width: 3),
            borderRadius: BorderRadius.circular(10),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(
              // color: Pallete.gradient2,
              width: 3,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      home: StreamBuilder(
        stream: FirebaseAuth.instance.authStateChanges(),

        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data != null) {
            return const MyHomePage();
          }
          return const SignUpPage();
        },
      ),
    );
  }
}
