import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
//import 'package:permission_handler/permission_handler.dart';
// import 'dart:convert';
// import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
//import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:lbp_app/notifications_service.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  LatLng? _currentPosition;
  GoogleMapController? _mapController;
  Set<Marker> markers = {}; // Declare markers to store disaster locations

  final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  @override
  void initState() {
    super.initState();
    _determinePosition();
    // // Request permission for notifications on iOS
    // FirebaseMessaging.instance.requestPermission();
    // // Get the FCM token
    // FirebaseMessaging.instance.getToken().then((token) {
    //   print("FCM Token: $token");
    // });
    subscribeToEarthquakeAlerts();
    // Setup message listener for foreground notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print(
        'Received a message in the foreground: ${message.notification?.title}',
      );
      if (message.notification != null) {
        NotificationService.showNotification(
          message,
        ); // Show local notification
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${message.notification?.title}: ${message.notification?.body}',
          ),
        ),
      );
    });

    // Optionally get the FCM token here
    FirebaseMessaging.instance.getToken().then((token) {
      print("FCM Token in Home Page: $token");
    });
  }

  // Function to handle subscribing to the notification topic
  Future<void> subscribeToEarthquakeAlerts() async {
    await FirebaseMessaging.instance.subscribeToTopic("earthquake-alerts");
    print("Subscribed to earthquake-alerts topic!");
  }

  // Method to check permissions and get current location
  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location services are disabled. Please enable them.'),
        ),
      );
      return;
    }

    // Check for permission
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permissions are permanently denied'),
        ),
      );
      return;
    }

    // Permissions are granted, proceed to get the current position
    try {
      LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high, // Set accuracy preference
        distanceFilter: 10, // Optional: Update location every 10 meters
      );
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });

      // Animate camera to current user location after map created
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_currentPosition!, 15),
        );
      }
      await fetchAlerts(); // Fetch alerts after getting current position
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  // Future<void> _getCurrentLocation() async {
  //   // Check permissions
  //   bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  //   if (!serviceEnabled) return;

  //   LocationPermission permission = await Geolocator.checkPermission();
  //   if (permission == LocationPermission.denied) {
  //     permission = await Geolocator.requestPermission();
  //     if (permission != LocationPermission.whileInUse) return;
  //   }

  //   // Get coordinates
  //   Position position = await Geolocator.getCurrentPosition();
  //   setState(() {
  //     _currentPosition = LatLng(position.latitude, position.longitude);
  //   });
  //   _mapController?.animateCamera(
  //     CameraUpdate.newLatLngZoom(_currentPosition!, 15),
  //   );
  // }

  // Future<void> fetchAlerts() async {
  //   String url =
  //       'https://us-central1-lbp-app-5e8a6.cloudfunctions.net/userAlertTrigger'; // Update this URL

  //   try {
  //     final response = await http.get(Uri.parse(url));
  //     if (response.statusCode == 200) {
  //       // Clear previous markers
  //       markers.clear();

  //       // Process the alerts
  //       final List<dynamic> alertsData = jsonDecode(response.body);
  //       for (var alert in alertsData) {
  //         double lat = alert['location']['latitude'];
  //         double lng = alert['location']['longitude'];
  //         String title =
  //             "${alert['description']} (Magnitude: ${alert['magnitude']})"; // Title includes magnitude

  //         // Create markers for each alert
  //         markers.add(
  //           Marker(
  //             markerId: MarkerId(alert['id']),
  //             position: LatLng(lat, lng),
  //             infoWindow: InfoWindow(title: title),
  //           ),
  //         );
  //       }
  //       setState(() {}); // Refresh the UI to show new markers
  //     } else {
  //       print('Failed to fetch alerts: ${response.body}');
  //     }
  //   } catch (error) {
  //     print('Error fetching alerts: $error');
  //   }
  // }

  Future<void> fetchAlerts() async {
    // Access the 'disasters' collection
    final disasterCollection = FirebaseFirestore.instance.collection(
      'disasters',
    );

    try {
      // Fetch all documents from the collection
      final querySnapshot = await disasterCollection.get();
      print('Fetched ${querySnapshot.docs.length} alerts.');

      // Conditional clearing of markers
      if (querySnapshot.docs.isNotEmpty) {
        setState(() {
          markers.clear();
        });
      }

      // Loop through the fetched documents
      for (var doc in querySnapshot.docs) {
        GeoPoint location = doc['location'];
        String description = doc['description'] ?? 'No description';
        // double magnitude = doc['magnitude'] ?? 0.0;
        var magnitudeValue = doc['magnitude'];
        double magnitude =
            (magnitudeValue is double)
                ? magnitudeValue
                : (magnitudeValue is int)
                ? magnitudeValue.toDouble()
                : 0.0;
        Timestamp timestamp = doc['timestamp'] ?? Timestamp.now();
        //.data()
        // Extract latitude and longitude from GeoPoint
        double lat = location.latitude;
        double lng = location.longitude;

        String formattedTime =
            DateTime.fromMillisecondsSinceEpoch(
              timestamp.millisecondsSinceEpoch,
            ).toString();

        String title = "$description (Magnitude: $magnitude)";
        String snippet = "Time: $formattedTime";

        // Create a marker for each disaster
        markers.add(
          Marker(
            markerId: MarkerId(doc.id), // Use Firestore document ID
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(title: title, snippet: snippet),
          ),
        );
      }

      // Refresh the UI with the new markers
      setState(() {});
      print('Markers added: ${markers.length}');
    } catch (error) {
      print('Error fetching alerts: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    //Set<Marker> markers = {};
    TextEditingController searchController = TextEditingController();

    if (_currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('user_location_marker'),
          position: _currentPosition!,
          infoWindow: const InfoWindow(title: 'Your Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alert Wave'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _signOut(context);
            },
          ),
        ],
        //centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: "Search...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4.0),
                ),
              ),
            ),
          ),
          Expanded(
            child: GoogleMap(
              //onMapCreated: (controller) => _mapController = controller,
              gestureRecognizers:
                  Set()..add(
                    Factory<PanGestureRecognizer>(() => PanGestureRecognizer()),
                  ),

              initialCameraPosition: CameraPosition(
                //target: _currentPosition ?? const LatLng(20.5937, 78.9629),
                target: LatLng(0, 0),
                zoom: 1,
              ),
              markers: markers,
              myLocationEnabled: true, // Shows blue dot
              myLocationButtonEnabled: true,
              // markers:
              //     _currentPosition != null
              //         ? {
              //           Marker(
              //             markerId: MarkerId("_currentLocation"),
              //             icon: BitmapDescriptor.defaultMarker,
              //             position: _currentPosition!,
              //           ),
              //         }
              //         : {},
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
                // if (_currentPosition != null) {
                //   _mapController!.animateCamera(
                //     CameraUpdate.newLatLngZoom(_currentPosition!, 15),
                //   );
                // }
                fetchAlerts(); // Fetch alerts when the map is created
              },
            ),
          ),
          Container(child: Column(mainAxisAlignment: MainAxisAlignment.center)),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      // No need to navigate, the StreamBuilder in main.dart will handle it
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error signing out: $e')));
      }
    }
  }
}
