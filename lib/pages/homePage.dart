import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll2;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:safety_of_sisters/pages/dailyCrimePage.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'dart:developer';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../components/utils.dart';
import '../components/safetyZoneList.dart' as safeZone;
import '../components/emergencyUserList.dart' as eUser;

import 'emergencyAIChatPage.dart';
import 'safetyLocationPage.dart';
import 'emergencyUsersPage.dart';
import 'emergencyContactPage.dart';
import 'emergencyChatPage.dart';
import 'crimeHistoryPage.dart';

class HomePage extends StatefulWidget {
  final UserCredential userCredential;

  const HomePage({Key? key, required this.userCredential}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<safeZone.SafetyZone> _nearestSafetyZone = [];

  String _userId = '';
  String _userName = '';
  String _userState = '';
  String _emergencyType = '';

  final String placeAPIKey = "YOUR_API_KEY";
  gm.LatLng? _selectedSafetyZone;
  StreamSubscription<Position>? _currentPositionSubscription;

  fm.MapController? _mapController;
  Position? _currentPosition;
  bool _isLoading = true;
  final List<fm.Marker> _markers = [];
  List<Map<String, dynamic>> _messages = [];

  // Change camera controller to nullable and lazy initialization
  CameraController? _cameraController;
  bool _isCameraInitialized = false;

  bool _isHelpingAnyone = false;
  String? _helpingUserId;
  eUser.EmergencyUser? _helpingUser;

  StreamSubscription<QuerySnapshot>? _chatStreamSubscription;

  late String _locationText = "Tracking Location...";
  StreamSubscription<List<DocumentSnapshot<Map<String, dynamic>>>>?
      _geoSubscription;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  double _currentZoom = 13.0;
  double _currentRadius = 5.0;

  // For reset to normal state
  int _profileTapCount = 0;
  Timer? _profileTapTimer;
  final int _requiredTaps = 3;
  final Duration _tapTimeWindow = Duration(seconds: 5);

  List<eUser.EmergencyUser> _nearbyEmergencyUsers = [];
  Stream<List<DocumentSnapshot<Map<String, dynamic>>>>? _emergencyUsersStream;
  eUser.EmergencyUser? _selectedEmergencyUser;
  StreamSubscription<List<DocumentSnapshot<Map<String, dynamic>>>>?
      _emergencyUsersSubscription;

  int _unreadMessagesCount = 0;
  Timestamp? _lastSeenTimestamp;

  final Map<double, double> _zoomRadiusMap = {
    19.0: 0.5,
    17.0: 1.0, // Very zoomed in: 1km radius
    15.0: 3.0, // Zoomed in: 3km radius
    13.0: 5.0, // Medium-close: 5km radius
    11.0: 10.0, // Medium: 10km radius
    10.0: 12.0, // Medium-far: 12km radius
    9.0: 15.0, // Far: 15km radius
    8.0: 20.0, // Very far: 20km radius
    7.0: 25.0, // Distant: 25km radius
    6.0: 30.0 // Very distant: 30km radius
  };

  @override
  void initState() {
    super.initState();
    _initUserState();
    _initHelpingStatus();
    _getCurrentLocation();
    _initPhoneSMS();
    _initNotifications();
    if (_userState == "emergency" || _helpingUserId != null) {
      _setupMessageListener();
    }
  }

  void _initNotifications() async {
    final AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await _notificationsPlugin.initialize(initializationSettings);
  }

  void _initUserState() {
    _userId = widget.userCredential.user!.uid;
    _userName = widget.userCredential.user!.displayName!;
    usersCollection.doc(_userId).snapshots().listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data() as Map<String, dynamic>;
        setState(() {
          _userState = data['status'] ?? 'normal';
          _emergencyType = data['emergencyType'] ?? 'SOS';
        });
      }
    });
  }

  void _initHelpingStatus() async {
    try {
      DocumentSnapshot curUserData = await usersCollection.doc(_userId).get();
      if (curUserData['helpingUserId'] != null) {
        DocumentSnapshot helpingUserData =
            await usersCollection.doc(curUserData['helpingUserId']).get();
        // final helpedUserDoc = helpingQuery.docs.first;
        // final helpedUserData = helpedUserDoc.data() as Map<String, dynamic>;

        // Extract GeoPoint from the position data
        GeoPoint geoPoint = helpingUserData['position']['geopoint'];

        // Calculate distance if current position is available
        double distance = 0;
        if (_currentPosition != null) {
          distance = calculateStraightLineDistance(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              geoPoint.latitude,
              geoPoint.longitude);
        }

        // Create EmergencyUser object for the user being helped
        final helpedUser = eUser.EmergencyUser(
          id: curUserData['helpingUserId'],
          name: helpingUserData['username'],
          phoneNumber: helpingUserData['handphone'],
          location: geoPoint,
          distance: distance,
          helpersCount: helpingUserData['helpersCount'] ?? 0,
          helpersOnTheWay: List<String>.from(
            helpingUserData['helpersOnTheWay'] ?? [],
          ),
          emergencyType: helpingUserData['emergencyType'] ?? 'Unknown',
          timestamp: (helpingUserData['emergencyAt']).toDate(),
        );

        setState(() {
          _isHelpingAnyone = true;
          _helpingUserId = curUserData['helpingUserId'];
          _helpingUser = helpedUser;
        });
      } else {
        setState(() {
          _isHelpingAnyone = false;
          _helpingUserId = null;
          _helpingUser = null;
        });
      }
      log(_isHelpingAnyone.toString());
    } catch (e) {
      log('Error checking helping status: $e');
    }
  }

  // Remove _initCamera() from initState and make it async
  Future<void> _initCamera() async {
    if (_isCameraInitialized) return;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        log("No cameras available");
        return;
      }

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController?.initialize();
      _isCameraInitialized = true;
      log("Camera initialized");
    } catch (e) {
      log("Error initializing camera: $e");
      _isCameraInitialized = false;
      _cameraController?.dispose();
      _cameraController = null;
    }
  }

  Future<void> _initPhoneSMS() async {
    bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
    log("Phone and SMS permissions: ${permissionsGranted.toString()}");
  }

void _setupMessageListener() async {
  // Cancel existing subscription if any
  _chatStreamSubscription?.cancel();

  if (_helpingUser == null) {
    log("No helping user, skipping message listener setup");
    return;
  }

  String chatRoomId = "emergency_${((_userState == "emergency") ? _userId : _helpingUser!.id)}";
  log("Setting up message listener for chat room: $chatRoomId");

  try {
    var t = await emergencyChatRoom.doc(chatRoomId).collection("messages").get();
    log(t.docs.toString());
    // Directly set up the message listener without waiting for initial document fetch
    _chatStreamSubscription = emergencyChatRoom
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen(
      (snapshot) {
        log(snapshot.docs.toString());
        log("Received message update. Messages count: ${snapshot.docs.length}");
        
        // Fetch the latest last seen timestamp
        emergencyChatRoom.doc(chatRoomId).get().then((chatRoom) {
          if (chatRoom.exists) {
            final data = chatRoom.data() as Map<String, dynamic>;
            if (data['participantDetails'] != null &&
                data['participantDetails'][_userId] != null) {
              _lastSeenTimestamp = data['participantDetails'][_userId]['lastSeen'];
            }

            // Calculate unread messages
            final messages = snapshot.docs.map((doc) => doc.data()).toList();
            int newUnreadCount = 0;
            if (_lastSeenTimestamp != null) {
              newUnreadCount = messages
                  .where((msg) =>
                      msg['timestamp'] != null &&
                      (msg['timestamp'] as Timestamp).compareTo(_lastSeenTimestamp!) > 0 &&
                      msg['senderId'] != _userId)
                  .length;
            }

            // Show notification and update state
            if (messages.isNotEmpty &&
                messages.length > _messages.length &&
                newUnreadCount > 0) {
              _showChatNotification(messages.last);
            }

            setState(() {
              _messages = messages;
              _unreadMessagesCount = newUnreadCount;
            });
          }
        }).catchError((error) {
          log("Error fetching chat room details: $error");
        });
      },
      onError: (error) {
        log("Error in message listener: $error");
      },
      cancelOnError: false,
    );

    log("Message listener setup completed");
  } catch (e) {
    log("Error setting up message listener: $e");
  }
}
  Future<void> _showChatNotification(Map<String, dynamic> message) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'emergency_chat_channel',
      'Emergency Chat Notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    log("Notification check - Message sender: ${message["senderName"]}");
    log("Notification check - Current user: $_userName");
    log("Notification check - Sender ID: ${message["senderId"]}");
    log("Notification check - Current user ID: $_userId");

    if (message['senderId'] == _userId) {
      log("Skipping notification - message is from current user");
      return;
    }
    String senderName = message['senderName'] ?? 'Someone';
    String messageText = message['text'] ?? '';

    await _notificationsPlugin.show(
      0, // notification id
      'Emergency Chat: ${_helpingUser!.name}',
      '$senderName: $messageText',
      platformChannelSpecifics,
    );
  }

  void _initChatNotifications() {
    // Only set up notifications if user is in emergency state
    if (_userState == 'emergency') {
      final chatRef =
          emergencyChatRoom.doc('emergency_$_userId').collection('messages');

      _chatStreamSubscription = chatRef
          .where('senderId', isNotEqualTo: _userId) // Don't count own messages
          .where('isRead', isEqualTo: false) // Only unread messages
          .snapshots()
          .listen((snapshot) {
        setState(() {});
      });
    }
  }

  Future<void> _refresh() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );
      setState(() {
        _locationText =
            "Lat:${position.latitude.toStringAsFixed(6)}\nLog:${position.longitude.toStringAsFixed(6)}";
        _currentPosition = position;
        updateUserLocation(_userId, position);
        _fetchNearbySafetyPlaces();
        _startStreamingNearbyEmergencyUsers();
      });
    } catch (e) {
      log('Error getting current location: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      _currentPositionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((Position position) {
        setState(() {
          _locationText =
              "Lat:${position.latitude.toStringAsFixed(6)}\nLog:${position.longitude.toStringAsFixed(6)}";
          _currentPosition = position;
          updateUserLocation(_userId, position);
          _fetchNearbySafetyPlaces();
          _startStreamingNearbyEmergencyUsers();
        });
      });
    } catch (e) {
      log('Error getting current location: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Currently having problem due to underlying camera plugin which returns .temp file
  // However, we cannot downgrade the current version otherwise the preview of video recording in
  // AI chat screen will having problem.
  Future<void> startVideoRecording() async {
    if (_cameraController == null) {
      await _initCamera();
    }

    if (_cameraController == null || !_isCameraInitialized) {
      log("Camera not initialized");
      return;
    }

    try {
      // Ensure any previous recording is stopped
      if (_cameraController!.value.isRecordingVideo) {
        await _cameraController!.stopVideoRecording();
      }

      // Reset camera settings before recording
      await _cameraController!.setFocusMode(FocusMode.auto);
      await _cameraController!.setExposureMode(ExposureMode.auto);

      log("Starting video recording");
      await _cameraController!.startVideoRecording();

      // Record for 11 seconds
      await Future.delayed(Duration(seconds: 11));

      final XFile videoFile = await _cameraController!.stopVideoRecording();
      log("Video recording completed: ${videoFile.path}");

      // Release camera resources
      await _cameraController!.dispose();
      await _initCamera(); // Reinitialize for next use

      // Move file to permanent storage
      final Directory? externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        throw Exception('Cannot access external storage');
      }

      final String filePath = '${externalDir.path}/SOS_Triggered.mp4';
      final File videoSource = File(videoFile.path);
      final File videoDest = await videoSource.copy(filePath);
      
      // Clean up temporary file
      await videoSource.delete();

      log("Video saved permanently at: ${videoDest.path}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Video saved successfully')),
      );
    } catch (e) {
      log("Error during video recording: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to record video: $e')),
      );
    } finally {
      // Cleanup camera resources after recording
      await _cameraController?.dispose();
      _cameraController = null;
      _isCameraInitialized = false;
    }
  }

  Future<List<safeZone.SafetyZone>> _fetchPlacesByType(
      List<String> placeTypes) async {
    if (_currentPosition == null) return [];

    List<safeZone.SafetyZone> result = [];

    try {
      // Get the current location coordinates.
      final double lat = _currentPosition!.latitude;
      final double lng = _currentPosition!.longitude;

      final uri = Uri.parse(
        'https://places.googleapis.com/v1/places:searchNearby',
      );

      // Request body
      final requestBody = {
        'includedTypes': placeTypes,
        'maxResultCount': 20,
        'locationRestriction': {
          'circle': {
            'center': {'latitude': lat, 'longitude': lng},
            'radius': 5000.0,
          },
        },
        "rankPreference": "DISTANCE"
      };

      // Headers
      final headers = {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': placeAPIKey,
        'X-Goog-FieldMask':
            'places.displayName,places.formattedAddress,places.location,places.id,places.nationalPhoneNumber,places.types',
      };

      log("Fetching Places using URL: $uri");

      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final placesData = data['places'] ?? [];

        for (var place in placesData) {
          final placeId = place['id'] as String;
          final name = place['displayName']["text"] as String;
          final location = gm.LatLng(
            place['location']['latitude'],
            place['location']['longitude'],
          );

          String phoneNumber = "Not available";
          if (place.containsKey("nationalPhoneNumber")) {
            phoneNumber = place["nationalPhoneNumber"];
          }

          String address = place["formattedAddress"] ?? "Address not available";
          String type = "Safety Place";

          if (place.containsKey("types") && place["types"].isNotEmpty) {
            type = formatPlaceType(place["types"][0]);
          }

          result.add(
            safeZone.SafetyZone(
              id: placeId,
              name: name,
              address: address,
              type: type,
              location: location,
              phoneNumber: phoneNumber,
            ),
          );
        }
      } else {
        log("HTTP error: ${response.statusCode}");
        log("Response: ${response.body}");
      }
    } catch (e) {
      log("Exception fetching places by type '$placeTypes': $e");
    }

    return result;
  }

  Future<void> _fetchNearbySafetyPlaces() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // List of place types to search for safety places
      List<String> safetyPlaceTypes = [
        'police',
        'hospital',
        'fire_station',
        'pharmacy',
        'doctor',
      ];

      // Fetch places from Google Places API
      final places = await _fetchPlacesByType(safetyPlaceTypes);

      // Calculate straight-line distances for each safety zone
      for (var zone in places) {
        zone.distance = calculateStraightLineDistance(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            zone.location.latitude,
            zone.location.longitude);
      }
      // places.sort((a, b) => a.distance.compareTo(b.distance));

      setState(() {
        _nearestSafetyZone = places;
        _isLoading = false;
      });
    } catch (e) {
      log('Error fetching safety places: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _selectSafetyZone(safeZone.SafetyZone zone) {
    setState(() {
      _selectedSafetyZone = zone.location;
    });

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildPlaceDetails(zone),
    );
  }

  Widget _buildPlaceDetails(safeZone.SafetyZone zone) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                safeZone.getIconForType(zone.type),
                color: safeZone.getTypeColor(zone.type),
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  zone.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.local_offer, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                zone.type,
                style: TextStyle(
                  fontSize: 16,
                  color: safeZone.getTypeColor(zone.type),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(zone.address, style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.phone, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(zone.phoneNumber, style: const TextStyle(fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.directions_walk, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                'Approximately ${(zone.distance / 1000).toStringAsFixed(2)} km away',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _navigateToSafeZone(zone),
              icon: const Icon(Icons.directions),
              label: const Text('Navigate', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: safeZone.getTypeColor(zone.type),
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                _makePhoneCall(zone.phoneNumber);
              },
              icon: const Icon(Icons.call),
              label: const Text('Call', style: TextStyle(fontSize: 16)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                foregroundColor: safeZone.getTypeColor(zone.type),
                side: BorderSide(color: safeZone.getTypeColor(zone.type)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNearestLocationSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_nearestSafetyZone.isNotEmpty)
        safeZone.SafetyPlaceCard(
          safetyZone: _nearestSafetyZone[0],
          onPlaceSelected: _selectSafetyZone,
          selectedZoneLocation: _selectedSafetyZone,
        )
      else
        const Center(
          child: Text(
            'No safety zones found nearby',
            style: TextStyle(fontSize: 16),
          ),
        ),
    ]);
  }

  void _selectEmergencyUser(eUser.EmergencyUser emergencyUser) {
    setState(() {
      _selectedEmergencyUser = emergencyUser;
    });

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildUserDetails(emergencyUser),
    );
  }

  Widget _buildNearestEUserSection() {
    return
        // Wrap the entire Column in an Expanded
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_nearbyEmergencyUsers.isNotEmpty)
        eUser.EmergencyUserCard(
            emergencyUser: _nearbyEmergencyUsers[0],
            onUserSelected: _selectEmergencyUser,
            selectedUser: _selectedEmergencyUser,
            currentUserId: _userId,
            isHelpingAnyone: _isHelpingAnyone,
            helpingUserId: _helpingUserId)
      else
        const Center(
          child: Text(
            'No emergency user found nearby',
            style: TextStyle(fontSize: 16),
          ),
        ),
    ]);
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }

  void _onMapZoomChanged(double zoom) {
    log(zoom.toString());
    log(_currentRadius.toString());
    // Only update if zoom level has meaningfully changed
    if ((zoom - _currentZoom).abs() >= 0.5) {
      _currentZoom = zoom;
      // If the radius would change based on new zoom, update subscription
      double newRadius = _getRadiusForZoom(zoom);
      _currentRadius = newRadius;
    }
  }

  double _getRadiusForZoom(double zoom) {
    // Find the closest zoom level in our map
    final sortedZoomLevels = _zoomRadiusMap.keys.toList()..sort();

    // If zoom is higher than our highest defined level, use the smallest radius
    if (zoom > sortedZoomLevels.last) {
      return _zoomRadiusMap[sortedZoomLevels.last] ?? 1.0;
    }

    // If zoom is lower than our lowest defined level, use the largest radius
    if (zoom < sortedZoomLevels.first) {
      return _zoomRadiusMap[sortedZoomLevels.first] ?? 30.0;
    }

    // Find the closest defined zoom level
    for (int i = 0; i < sortedZoomLevels.length; i++) {
      if (zoom >= sortedZoomLevels[i]) {
        // If this is the last entry or zoom is closer to this level than the next
        if (i == sortedZoomLevels.length - 1 ||
            (sortedZoomLevels[i + 1] - zoom) > (zoom - sortedZoomLevels[i])) {
          return _zoomRadiusMap[sortedZoomLevels[i]] ?? 5.0;
        }
      }
    }

    // Default fallback
    return 5.0;
  }

  void _showCrimeDetails(BuildContext context, Map<String, dynamic> crimeData) {
    // Convert Firestore Timestamp to DateTime.
    DateTime crimeTime = crimeData['datetime'] != null
        ? (crimeData['datetime'] as Timestamp).toDate()
        : DateTime.now();

    // Format date and time nicely
    String formattedDate =
        "${crimeTime.day}/${crimeTime.month}/${crimeTime.year}";
    String formattedTime =
        "${crimeTime.hour.toString().padLeft(2, '0')}:${crimeTime.minute.toString().padLeft(2, '0')}";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding: EdgeInsets.all(16),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Row(
          children: [
            crimeIcon(crimeData['type'] ?? ''),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                crimeData['type'] ?? 'Unknown Crime',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Date', formattedDate),
            SizedBox(height: 8),
            _buildDetailRow('Time', formattedTime),
            SizedBox(height: 8),
            _buildDetailRow(
                'Address', crimeData['address'] ?? 'Unknown Address'),
            if (crimeData['description'] != null) ...[
              SizedBox(height: 16),
              Text(
                'Description:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 4),
              Text(crimeData['description']),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildMapSection() {
    if (_currentPosition == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Cancel previous subscription if it exists
    _geoSubscription?.cancel();

    // Create a GeoFirePoint from the current position
    final geoPoint = GeoFirePoint(
        GeoPoint(_currentPosition!.latitude, _currentPosition!.longitude));
    GeoCollectionReference(
            crimeCollection as CollectionReference<Map<String, dynamic>>)
        .subscribeWithin(
            center: geoPoint,
            radiusInKm: _currentRadius,
            field: 'location',
            geopointFrom: (data) {
              return data['location']['geopoint'] as GeoPoint;
            })
        .listen((documentList) {
      _markers.clear();
      _markers.add(
        fm.Marker(
          point: ll2.LatLng(
              _currentPosition!.latitude, _currentPosition!.longitude),
          width: 80,
          height: 80,
          child: const Icon(
            Icons.my_location,
            color: Colors.blue,
            size: 30,
          ),
        ),
      );
      setState(() {
        for (var doc in documentList) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          var location = ll2.LatLng(data["location"]["geopoint"].latitude,
              data["location"]["geopoint"].longitude);
          _markers.add(
            fm.Marker(
              width: 40.0,
              height: 40.0,
              point: location,
              child: GestureDetector(
                onTap: () => _showCrimeDetails(context, data),
                child: crimeIcon(data['type'] ?? ''),
              ),
            ),
          );
        }
      });
    });

    return Container(
      height: 300,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            spreadRadius: 1,
            blurRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: fm.FlutterMap(
          mapController: _mapController,
          options: fm.MapOptions(
            onLongPress: (tapPosition, position) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CrimeMapScreen(userId: _userId),
                ),
              );
            },
            interactionOptions: const fm.InteractionOptions(
              flags: fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate,
            ),
            initialCenter: ll2.LatLng(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
            ),
            initialZoom: _currentZoom,
            onMapEvent: (event) {
              if (event is fm.MapEventWithMove) {
                _onMapZoomChanged(event.camera.zoom);
              }
            },
          ),
          children: [
            fm.TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            ),
            fm.MarkerLayer(markers: _markers),
          ],
        ),
      ),
    );
  }

  void _navigateToSafeZone(safeZone.SafetyZone zone) async {
    var flag = await navigateToGoogleMaps(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        zone.location.latitude,
        zone.location.longitude);
    if (flag == false) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error opening navigation')));
    }
  }

  void _navigateToEUser(eUser.EmergencyUser emergencyUser) async {
    var flag = await navigateToGoogleMaps(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        emergencyUser.location.latitude,
        emergencyUser.location.longitude);

    if (flag == false) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error opening navigation')));
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    var flag = await makePhoneCall(phoneNumber);
    if (flag == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch phone call')),
      );
    }
  }

  void _openChat() {
    if (_userState == "emergency") {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EmergencyGroupChatScreen(
            currentUserId: _userId,
            emergencyUserId: _userId,
            emergencyUserName: _userName,
            emergencyType: _emergencyType,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EmergencyGroupChatScreen(
            currentUserId: _userId,
            emergencyUserId: _helpingUser!.id,
            emergencyUserName: _helpingUser!.name,
            emergencyType: _helpingUser!.emergencyType,
          ),
        ),
      );
    }
  }

  void _handleProfileTap() {
    setState(() {
      _profileTapCount++;
    });

    // Cancel existing timer if there is one
    _profileTapTimer?.cancel();

    // If we've reached the required number of taps
    if (_profileTapCount >= _requiredTaps) {
      _resetEmergencyStatus();
      _profileTapCount = 0;
    } else {
      // Start a new timer
      _profileTapTimer = Timer(_tapTimeWindow, () {
        // Reset counter if time window expires
        setState(() {
          _profileTapCount = 0;
        });
      });
    }
  }

  void _resetEmergencyStatus() async {
    try {
      // Reset the emergency status to normal
      log('emergency_$_userId');
      emergencyChatRoom.doc('emergency_$_userId').delete().then(
            (doc) => log("Group Chat Room deleted"),
            onError: (e) => log("Error updating document $e"),
          );
      DocumentSnapshot userDoc = await usersCollection.doc(_userId).get();
      List<String> helpersOnTheWay =
          List<String>.from(userDoc.get('helpersOnTheWay') ?? []);
      await usersCollection.doc(_userId).set({
        'status': 'normal',
        'emergencyType': null,
        'emergencyAt': null,
        'helpersOnTheWay': [],
        'helpersCount': 0,
      }, SetOptions(merge: true));

      for (String helperId in helpersOnTheWay) {
        await usersCollection.doc(helperId).set({
          'helpingUserId': null,
        }, SetOptions(merge: true));
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency status reset to normal'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      log('Error resetting emergency status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to reset emergency status'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _signOut() async {
    try {
      // Show a confirmation dialog
      bool confirm = await showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text("Sign Out"),
                content: const Text("Are you sure you want to sign out?"),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text("CANCEL"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text("SIGN OUT"),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              );
            },
          ) ??
          false;

      if (confirm) {
        // Reset any emergency status before signing out
        // For testing, comment following lines:
        // await usersCollection.doc(_userId).set({
        //   'status': 'normal',
        //   'emergencyType': null,
        //   'emergencyAt': null,
        // }, SetOptions(merge: true));
        await FirebaseAuth.instance.signOut();
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      log('Error signing out: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to sign out'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _offerHelp(eUser.EmergencyUser emergencyUser) async {
    if (_userState == "emergency") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are in emergency!')),
      );
      return;
    }

    try {
      DocumentReference emergencyUserRef =
          usersCollection.doc(emergencyUser.id);

      if (emergencyUser.helpersOnTheWay.contains(_userId)) {
        // Cancel help
        _cancelHelp();
      } else {
        // Offer help
        if (_isHelpingAnyone) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('You are already helping ${_helpingUser!.name} else'),
            ),
          );
          return;
        }

        await emergencyUserRef.update({
          'helpersOnTheWay': FieldValue.arrayUnion([_userId]),
          'helpersCount': FieldValue.increment(1),
        });

        usersCollection
            .doc(_userId)
            .set({'helpingUserId': emergencyUser.id}, SetOptions(merge: true));

        // Update helping status
        setState(() {
          _isHelpingAnyone = true;
          _helpingUserId = emergencyUser.id;
          _helpingUser = emergencyUser;
        });

        _setupMessageListener();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You are now helping ${_helpingUser!.name}')),
        );
      }

      Navigator.pop(context);
    } catch (e) {
      log('Error updating help status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update help status')),
      );
    }
  }

  Future<void> _cancelHelp() async {
    if (!_isHelpingAnyone || _helpingUserId == null) return;

    try {
      DocumentReference userRef = usersCollection.doc(_helpingUserId);

      await userRef.update({
        'helpersOnTheWay': FieldValue.arrayRemove([_userId]),
        'helpersCount': FieldValue.increment(-1),
      });

      usersCollection
          .doc(_userId)
          .set({'helpingUserId': null}, SetOptions(merge: true));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('You are no longer helping ${_helpingUser!.name}')),
      );
      setState(() {
        _isHelpingAnyone = false;
        _helpingUserId = null;
        _helpingUser = null;
      });
      _chatStreamSubscription?.cancel();
    } catch (e) {
      log('Error canceling help: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to cancel help')));
    }
  }

  Widget _buildUserDetails(eUser.EmergencyUser emergencyUser) {
    bool isHelping = emergencyUser.helpersOnTheWay.contains(_userId);
    bool canHelp = !_isHelpingAnyone ||
        (_helpingUserId != null && _helpingUserId == emergencyUser.id);

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  eUser.getIconForType(emergencyUser.emergencyType),
                  color: eUser.getTypeColor(emergencyUser.emergencyType),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    emergencyUser.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.warning, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  emergencyUser.emergencyType,
                  style: TextStyle(
                    fontSize: 16,
                    color: eUser.getTypeColor(emergencyUser.emergencyType),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Emergency reported: ${eUser.formatTimestampEmergency(emergencyUser.timestamp)}',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.phone, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(emergencyUser.phoneNumber,
                    style: const TextStyle(fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.people, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  '${emergencyUser.helpersCount} helpers on the way',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.directions_walk, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Approximately ${(emergencyUser.distance / 1000).toStringAsFixed(2)} km away',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _navigateToEUser(emergencyUser),
                icon: const Icon(Icons.directions),
                label: const Text('Navigate', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor:
                      eUser.getTypeColor(emergencyUser.emergencyType),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _makePhoneCall(emergencyUser.phoneNumber);
                    },
                    icon: const Icon(Icons.call),
                    label: const Text('Call', style: TextStyle(fontSize: 16)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: Colors.green,
                      side: BorderSide(color: Colors.green),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _openChat();
                    },
                    icon: const Icon(Icons.chat),
                    label: const Text('Chat', style: TextStyle(fontSize: 16)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canHelp
                        ? () {
                            _offerHelp(emergencyUser);
                          }
                        : null,
                    icon: Icon(
                        isHelping ? Icons.cancel : Icons.volunteer_activism),
                    label: Text(
                      isHelping ? 'Cancel Help' : 'Offer Help',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: isHelping ? Colors.grey : Colors.green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.grey.shade700,
                    ),
                  ),
                ),
                if (_isHelpingAnyone && !isHelping) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info, color: Colors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "You are already helping ${_helpingUser?.name ?? 'someone'}. You must cancel that help before offering help to someone else.",
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            )
          ]),
    );
  }

  void _startStreamingNearbyEmergencyUsers() async {
    final center = GeoFirePoint(
        GeoPoint(_currentPosition!.latitude, _currentPosition!.longitude));

    // Get nearby users within 10km
    double radiusInKm = 10.0;

    try {
      // Use subscribeWithin from geoflutterfire_plus on the users collection
      _emergencyUsersStream = GeoCollectionReference(
              usersCollection as CollectionReference<Map<String, dynamic>>)
          .subscribeWithin(
        center: center,
        radiusInKm: radiusInKm,
        field: 'position',
        geopointFrom: (data) {
          return data['position']['geopoint'] as GeoPoint;
        },
      );

      _emergencyUsersSubscription = _emergencyUsersStream!.listen(
        (List<DocumentSnapshot<Map<String, dynamic>>> documentList) {
          List<eUser.EmergencyUser> emergencyUsers = [];
          log("Hi");
          // Filter only users with emergency status
          for (var document in documentList) {
            Map<String, dynamic> data = document.data() as Map<String, dynamic>;

            if (document.id != _userId &&
                data["status"] != null &&
                data['status'] == 'emergency') {
              GeoPoint geoPoint = data['position']['geopoint'];

              double distance = calculateStraightLineDistance(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                  geoPoint.latitude,
                  geoPoint.longitude);

              emergencyUsers.add(
                eUser.EmergencyUser(
                  id: document.id,
                  name: data['username'],
                  phoneNumber: data['handphone'],
                  location: geoPoint,
                  distance: distance,
                  helpersCount: data['helpersCount'] ?? 0,
                  helpersOnTheWay: List<String>.from(
                    data['helpersOnTheWay'] ?? [],
                  ),
                  emergencyType: data['emergencyType'],
                  timestamp: (data['emergencyAt']).toDate(),
                ),
              );
            }
          }

          setState(() {
            List<eUser.EmergencyUser> previousUsers = _nearbyEmergencyUsers;
            _nearbyEmergencyUsers = emergencyUsers;

            // Sort by distance and helping status
            _nearbyEmergencyUsers.sort((a, b) {
              if (_isHelpingAnyone && a.id == _helpingUserId) return -1;
              if (_isHelpingAnyone && b.id == _helpingUserId) return 1;
              return a.distance.compareTo(b.distance);
            });

            // Notify only for the closest new emergency
            if (_nearbyEmergencyUsers.isNotEmpty) {
              bool isNewEmergency = previousUsers.isEmpty ||
                  !previousUsers
                      .any((user) => user.id == _nearbyEmergencyUsers[0].id);

              if (isNewEmergency &&
                  _nearbyEmergencyUsers[0].id != _userId &&
                  !_isHelpingAnyone) {
                String notificationBody = '''
Emergency Type: ${_nearbyEmergencyUsers[0].emergencyType}\n
Distance: ${(_nearbyEmergencyUsers[0].distance / 1000).toStringAsFixed(2)} km away\n
''';
log('Sending notification for new emergency');
                _showEmergencyNotification(
                    'Nearby Emergency: ${_nearbyEmergencyUsers[0].name}',
                    notificationBody);
              }
            }

            // Update helping user if needed
            if (_isHelpingAnyone && _helpingUserId != null) {
              _helpingUser = _nearbyEmergencyUsers.firstWhere(
                  (user) => user.id == _helpingUserId,
                  orElse: () => _helpingUser!);
            }
          });
        },
        onError: (error) {
          log('Error streaming nearby emergency users: $error');
        },
        cancelOnError: false,
      );
    } catch (e) {
      log('Error setting up emergency users stream: $e');
    }
  }

  void _showEmergencyNotification(String title, String info) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'emergency_channel',
      'Emergency Alerts',
      channelDescription: 'Notifies when an emergency is nearby',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );
    await _notificationsPlugin.show(
      0,
      title,
      info,
      notificationDetails,
      payload: 'emergency',
    );
  }

  // Helper widget to show who the user is helping
  Widget _buildHelpingBanner() {
    if (!_isHelpingAnyone || _helpingUser == null)
      return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.green.shade50,
      child: Row(
        children: [
          Icon(
            eUser.getIconForType(_helpingUser!.emergencyType),
            color: Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "You are helping ${_helpingUser!.name}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  "Emergency type: ${_helpingUser!.emergencyType}",
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _cancelHelp,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Cancel Help"),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyTypeButton(
    BuildContext context,
    String type,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () async {
            Navigator.of(context).pop();
            // Set emergency status with selected type
            await usersCollection.doc(_userId).set({
              'status': 'emergency',
              'emergencyType': type,
              'emergencyAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

            // Only proceed with SMS if we have location
            if (_currentPosition != null) {
              try {
                // Spend the quota wisely!
                // EmergencyContactManager.notifyEmergencyContacts(_userId, _userName, _emergencyType, _currentPosition!.latitude, _currentPosition!.longitude);
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Navigate to Safety'),
                    content: Text(
                        'After sending the SMS, would you like to navigate to the nearest safe location?'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          if (_nearestSafetyZone.isNotEmpty) {
                            _navigateToSafeZone(_nearestSafetyZone.first);
                          }
                        },
                        child: Text('Yes, navigate now'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('No, stay on this screen'),
                      ),
                    ],
                  ),
                );
              } catch (e) {
                log("Error opening SMS app: $e");
                // Show error and ask if they want to navigate anyway
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('SMS Failed'),
                    content: Text(
                        'Unable to open SMS app. Would you like to navigate to the nearest safe location?'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          if (_nearestSafetyZone.isNotEmpty) {
                            _navigateToSafeZone(_nearestSafetyZone.first);
                          }
                        },
                        child: Text('Yes'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('No'),
                      ),
                    ],
                  ),
                );
              }
            } else {
              // No position available
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Location Unavailable'),
                  content: Text(
                      'Your location is unavailable. Unable to send SMS with location details.'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        if (_nearestSafetyZone.isNotEmpty) {
                          _navigateToSafeZone(_nearestSafetyZone.first);
                        }
                      },
                      child: Text('Navigate to safety anyway'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel'),
                    ),
                  ],
                ),
              );
            }
          },
          icon: Icon(icon, color: Colors.white),
          label: Text(type, style: const TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Safety Dashboard'),
          backgroundColor: Colors.red,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _refresh(),
              tooltip: 'Refresh',
            ),
            if (_userState == 'emergency' || _helpingUserId != null)
              IconButton(
                icon: const Icon(Icons.chat),
                onPressed: () => _openChat(),
                tooltip: 'Chat with helpers!',
              ),
          ],
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 246, 64, 94),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Safety Of Sisters',
                      style: TextStyle(color: Colors.white, fontSize: 22),
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            // Implement tap counting logic
                            _handleProfileTap();
                          },
                          child: CircleAvatar(
                            backgroundColor: Colors.white,
                            radius: 20,
                            child: Icon(
                              Icons.person,
                              color: const Color.fromARGB(255, 246, 64, 94),
                              size: 22,
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _userName,
                            style: TextStyle(color: Colors.white, fontSize: 18),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      _locationText,
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
              ListTile(
                  leading: Icon(Icons.map),
                  title: Text('Crime Map'),
                  onTap: () {
                    Navigator.pop(context); // Close the drawer
                    if (_currentPosition != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CrimeMapScreen(userId: _userId),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Location not available yet')),
                      );
                    }
                  }),
              ListTile(
                leading: Icon(Icons.contact_emergency),
                title: Text('Emergency Contact'),
                onTap: () {
                  Navigator.pop(context); // Close the drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            EmergencyContactsScreen(currentUserId: _userId)),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.newspaper),
                title: Text('Daily Crime'),
                onTap: () {
                  Navigator.pop(context); // Close the drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            CrimeNewsPage(currentUserId: _userId)),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.location_on),
                title: Text('Find Safety Zones'),
                onTap: () {
                  Navigator.pop(context); // Close the drawer
                  if (_currentPosition != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SafetyZoneMapScreen(
                            userName: _userName,
                            userId: _userId,
                            userState: _userState,
                            emergencyType: _emergencyType),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Location not available yet')),
                    );
                  }
                },
              ),
              ListTile(
                  leading: Icon(Icons.sos),
                  title: Text('Emergency Users'),
                  onTap: () {
                    Navigator.pop(context); // Close the drawer
                    if (_currentPosition != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NearbyEmergencyUsersScreen(
                            currentUserId: _userId,
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Location not available yet')),
                      );
                    }
                  }),
              ListTile(
                leading: Icon(Icons.smart_toy),
                title: Text('Emergency AI'),
                onTap: () {
                  Navigator.pop(context); // Close the drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AIChatScreen(
                        userId: _userId,
                        userName: _userName,
                      ),
                    ),
                  );
                },
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.settings),
                title: Text('Settings'),
                onTap: () {
                  Navigator.pop(context); // Close the drawer
                  // Navigate to settings page (not implemented)
                },
              ),
              ListTile(
                leading: Icon(Icons.help),
                title: Text('Help & About'),
                onTap: () {
                  Navigator.pop(context); // Close the drawer
                  // Navigate to help page (not implemented)
                },
              ),
              ListTile(
                leading: Icon(Icons.logout, color: Colors.red),
                title: Text('Sign Out', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context); // Close the drawer
                  _signOut();
                },
              ),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () => _refresh(),
                child: ListView(
                  padding: EdgeInsets.zero, // Ensure no unwanted padding
                  children: [
                    if (_isHelpingAnyone) _buildHelpingBanner(),
                    _buildMapSection(),
                    _buildNearestLocationSection(),
                    _buildNearestEUserSection(),
                  ],
                ),
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            // startVideoRecording();
            showDialog(
              context: context,
              barrierDismissible:
                  false, // User must select an option or wait for timeout
              builder: (BuildContext context) {
                // Set up a timer to auto-close after 3 seconds
                Timer(const Duration(seconds: 5), () {
                  // If dialog is still open after 3 seconds, close it and proceed with default SOS
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                    // Set emergency status with default type
                    setState(() {
                      _userState = 'emergency';
                    });
                    usersCollection.doc(_userId).set({
                      'status': 'emergency',
                      'emergencyType': 'SOS', // Default type
                      'emergencyAt': FieldValue.serverTimestamp(),
                      'helpersOnTheWay': [],
                      'helpersCount': 0,
                    }, SetOptions(merge: true));

                    if (_currentPosition != null) {
                      try {
                        // Show a dialog asking if they want to navigate to safety
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text('Navigate to Safety'),
                            content: Text(
                                'After sending the SMS, would you like to navigate to the nearest safe location?'),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  if (_nearestSafetyZone.isNotEmpty) {
                                    _navigateToSafeZone(
                                        _nearestSafetyZone.first);
                                  }
                                },
                                child: Text('Yes, navigate now'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('No, stay on this screen'),
                              ),
                            ],
                          ),
                        );
                      } catch (e) {
                        log("Error opening SMS app: $e");
                        // Show error and ask if they want to navigate anyway
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text('SMS Failed'),
                            content: Text(
                                'Unable to open SMS app. Would you like to navigate to the nearest safe location?'),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  if (_nearestSafetyZone.isNotEmpty) {
                                    _navigateToSafeZone(
                                        _nearestSafetyZone.first);
                                  }
                                },
                                child: Text('Yes'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('No'),
                              ),
                            ],
                          ),
                        );
                      }
                    } else {
                      // No position available
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('Location Unavailable'),
                          content: Text(
                              'Your location is unavailable. Unable to send SMS with location details.'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                if (_nearestSafetyZone.isNotEmpty) {
                                  _navigateToSafeZone(_nearestSafetyZone.first);
                                }
                              },
                              child: Text('Navigate to safety anyway'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text('Cancel'),
                            ),
                          ],
                        ),
                      );
                    }
                    // Navigate to the closest safety place
                  }
                });

                return AlertDialog(
                  title: const Text(
                    'Emergency Type',
                    style: TextStyle(color: Colors.red),
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildEmergencyTypeButton(
                          context,
                          'Medical',
                          Icons.medical_services,
                          Colors.red,
                        ),
                        _buildEmergencyTypeButton(
                          context,
                          'Crime',
                          Icons.security,
                          Colors.blue,
                        ),
                        _buildEmergencyTypeButton(
                          context,
                          'Accident',
                          Icons.car_crash,
                          Colors.orange,
                        ),
                        _buildEmergencyTypeButton(
                          context,
                          'Fire',
                          Icons.local_fire_department,
                          Colors.deepOrange,
                        ),
                        _buildEmergencyTypeButton(
                          context,
                          'Natural Disaster',
                          Icons.storm,
                          Colors.purple,
                        ),
                        _buildEmergencyTypeButton(
                          context,
                          'Other',
                          Icons.sos,
                          Colors.red,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          backgroundColor: const Color.fromARGB(255, 232, 95, 85),
          child: const Icon(Icons.sos),
        ));
  }

  @override
  void dispose() {
    // Cleanup camera resources
    if (_cameraController != null) {
      _cameraController?.dispose();
      _cameraController = null;
      _isCameraInitialized = false;
    }
    _currentPositionSubscription?.cancel();
    _chatStreamSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
}
