import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
//import 'package:cloud_firestore/cloud_firestore.dart';
//import 'package:geolocator_android/geolocator_android.dart';
import 'package:lbp_app/login_page.dart';
import 'package:lbp_app/home_page.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

class SignUpPage extends StatefulWidget {
  static route() => MaterialPageRoute(builder: (context) => const SignUpPage());
  const SignUpPage({super.key});
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  bool locationGranted = false;
  Position? userPosition;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable location services')),
      );
      return;
    }

    // LocationPermission permission = await Geolocator.checkPermission();
    // if (permission == LocationPermission.denied) {
    //   permission = await Geolocator.requestPermission();
    //   if (permission == LocationPermission.denied) {
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       const SnackBar(content: Text('Location permission denied')),
    //     );
    //     return;
    //   }
    // }

    // if (permission == LocationPermission.deniedForever) {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(
    //       content: Text('Location permissions are permanently denied'),
    //     ),
    //   );
    //   return;
    // }

    // // Permission granted
    // setState(() {
    //   locationGranted = true;
    // });

    // userPosition = await Geolocator.getCurrentPosition();

    // Check location permission status
    var status = await Permission.location.status;

    // Request permission if it is denied
    if (status.isDenied) {
      status = await Permission.location.request();
      if (status.isDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
        return;
      } else if (status.isPermanentlyDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are permanently denied'),
          ),
        );
        return;
      }
    }

    // If permission is granted, get the user's current position
    if (status.isGranted) {
      userPosition = await Geolocator.getCurrentPosition();
      setState(() {
        locationGranted =
            true; // Update the state to reflect permission granted
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Location obtained: Lat=${userPosition!.latitude}, Lon=${userPosition!.longitude}',
          ),
        ),
      );
    }
  }

  Future<String?> getFcmToken() async {
    // Get the Firebase Messaging instance
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Request permission to send notifications
    NotificationSettings settings = await messaging.requestPermission();

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission for notifications');
      // Get the FCM token
      String? fcmToken = await messaging.getToken();
      print("FCM Token: $fcmToken");
      return fcmToken;
    } else {
      print('User denied permission');
      return null;
    }
  }

  Future<void> createUserWithEmailAndPassword() async {
    if (!locationGranted || userPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please grant location permission first')),
      );
      return;
    }

    try {
      final UserCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: emailController.text.trim(),
            password: passwordController.text.trim(),
          );

      // Fetch the FCM token
      String? fcmToken = await getFcmToken();

      // After user creation, call addUser function
      String url =
          'https://us-central1-lbp-app-5e8a6.cloudfunctions.net/addUser'; // Replace with your actual URL
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': UserCredential.user!.uid,
          'email': emailController.text.trim(), // Add user email
          'alertsEnabled': true, // set as per requirements
          'token':
              fcmToken ??
              '', // You might need to fetch this after user login using Firebase Messaging
        }),
      );

      if (response.statusCode == 201) {
        print('User data added successfully!');
      } else {
        print('Failed to add user: ${response.body}');
      }

      // Save user location to Firestore under users collection with UID as doc ID
      // await FirebaseFirestore.instance
      //     .collection('users')
      //     .doc(UserCredential.user!.uid)
      //     .set({
      //       'email': emailController.text.trim(),
      //       'location': {
      //         'latitude': userPosition!.latitude,
      //         'longitude': userPosition!.longitude,
      //       },
      //       'createdAt': FieldValue.serverTimestamp(),
      //     });

      // Optionally navigate to home page directly or show success
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MyHomePage()),
        );
      }
    } on FirebaseAuthException catch (firebaseAuthEx) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(firebaseAuthEx.message ?? 'Sign up failed')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Sign Up.',
                style: TextStyle(fontSize: 50, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const SizedBox(height: 20),
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(hintText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty || !value.contains('@')) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: passwordController,
                decoration: const InputDecoration(
                  hintText: 'Create a Password',
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.length < 6) {
                    return 'Enter min 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  await requestLocationPermission();
                },
                child: const Text(
                  'LOCATION ACCESS',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    await createUserWithEmailAndPassword();
                  }
                },
                child: const Text(
                  'SIGN UP',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  Navigator.push(context, LoginPage.route());
                },
                child: RichText(
                  text: TextSpan(
                    text: 'Already have an account? ',
                    style: Theme.of(context).textTheme.titleMedium,
                    children: [
                      TextSpan(
                        text: 'Sign In',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
