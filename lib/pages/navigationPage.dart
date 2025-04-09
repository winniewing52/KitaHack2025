import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:developer';
import '../components/utils.dart';

class EmergencyNavigationScreen extends StatefulWidget {
  final String currentUserId;
  final String emergencyUserId;
  
  const EmergencyNavigationScreen({
    
    Key? key,
    required this.currentUserId,
    required this.emergencyUserId,
  }) : super(key: key);

  @override
  _EmergencyNavigationScreenState createState() => _EmergencyNavigationScreenState();
}

class _EmergencyNavigationScreenState extends State<EmergencyNavigationScreen> {
  final CollectionReference usersCollection = FirebaseFirestore.instance
      .collection('users');
  StreamSubscription<DocumentSnapshot>? _emergencyUserSubscription;
  StreamSubscription<Position>? _currentPositionSubscription;
  Position? _currentPosition;
  GeoPoint? _emergencyGeoPoint;
  bool _isNavigating = false;
  Timer? _navigationUpdateTimer;
  
  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _listenToEmergencyUserLocation();
  }

  @override
  void dispose() {
    _emergencyUserSubscription?.cancel();
    _currentPositionSubscription?.cancel();
    _navigationUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    
    // Start listening for current user's position updates
    // _currentPositionSubscription = Geolocator.getPositionStream(
    //   locationSettings: LocationSettings(
    //     accuracy: LocationAccuracy.high,
    //     distanceFilter: 10, // Update when moved at least 10 meters
    //   ),
    // ).listen((Position position) {
      setState(() async {
        Position? position = await getUserLocation(widget.currentUserId);
        _currentPosition = position;
      });
      
      // If user is actively navigating, update the navigation
      if (_isNavigating && _emergencyGeoPoint != null) {
        _openGoogleMapsNavigation(
          _emergencyGeoPoint!.latitude,
          _emergencyGeoPoint!.longitude,
          forceUpdate: false // Don't force to avoid app switching too often
        );
      }
    // });
  }

  void _listenToEmergencyUserLocation() {
    _emergencyUserSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.emergencyUserId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final userData = snapshot.data()!;
        log(widget.emergencyUserId);
        log(widget.currentUserId);
        if (userData['position'] != null) {
          final position = userData['position'] as Map<String, dynamic>;
          final geoPoint = position['geopoint'] as GeoPoint;
          // Check if location has significantly changed (more than 30 meters)
          bool significantChange = false;
          if (_emergencyGeoPoint != null) {
            double distance = Geolocator.distanceBetween(
              _emergencyGeoPoint!.latitude,
              _emergencyGeoPoint!.longitude,
              geoPoint.latitude,
              geoPoint.longitude
            );
            significantChange = distance > 30; // Only update if moved more than 30m
          } else {
            significantChange = true; // First update is always significant
          }
          
          setState(() {
            _emergencyGeoPoint = geoPoint;
            log('Emergency Location:' + _emergencyGeoPoint!.latitude.toString() + ", " + _emergencyGeoPoint!.longitude.toString());
          });
          
          // If navigating and location changed significantly, update navigation
          if (_isNavigating && significantChange && _currentPosition != null) {
            _openGoogleMapsNavigation(
              geoPoint.latitude,
              geoPoint.longitude,
              forceUpdate: true
            );
          }
        }
      }
    });
  }

  Future<void> _openGoogleMapsNavigation(double destLat, double destLng, {bool forceUpdate = false}) async {
    if (_currentPosition == null) return;
    
    try {
      final url = 'https://www.google.com/maps/dir/?api=1'
          '&origin=${_currentPosition!.latitude},${_currentPosition!.longitude}'
          '&destination=$destLat,$destLng'
          '&travelmode=walk';
      
      if (forceUpdate || !_isNavigating) {
        // Launch Maps app with URL
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          setState(() {
            _isNavigating = true;
          });
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not launch $url';
        }
      } else {
        // Store updated URL for the refresh button
        setState(() {});
      }
    } catch (e) {
      log('Error launching navigation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening Google Maps: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Emergency Navigation'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _emergencyGeoPoint != null
                ? () => _openGoogleMapsNavigation(
                    _emergencyGeoPoint!.latitude,
                    _emergencyGeoPoint!.longitude,
                    forceUpdate: true
                  )
                : null,
            tooltip: 'Refresh navigation',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.emergency,
              color: Colors.red,
              size: 64,
            ),
            SizedBox(height: 16),
            Text(
              'Emergency in Progress',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            if (_currentPosition != null && _emergencyGeoPoint != null)
              Text(
                'Distance: ${Geolocator.distanceBetween(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                  _emergencyGeoPoint!.latitude,
                  _emergencyGeoPoint!.longitude
                ).toStringAsFixed(2)} meters',
                style: TextStyle(fontSize: 16),
              ),
            SizedBox(height: 32),
            if (_emergencyGeoPoint != null) ...[
              ElevatedButton.icon(
                icon: Icon(Icons.navigation),
                label: Text(_isNavigating 
                  ? 'Continue Navigation' 
                  : 'Start Navigation to Emergency'
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () => _openGoogleMapsNavigation(
                  _emergencyGeoPoint!.latitude,
                  _emergencyGeoPoint!.longitude,
                  forceUpdate: true
                ),
              ),
              SizedBox(height: 16),
              Text(
                'This will open Google Maps with directions to the emergency location',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[600],
                ),
              ),
            ] else
              CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}