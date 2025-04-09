import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'package:http/http.dart' as http;
import 'package:safety_of_sisters/components/utils.dart';
import 'dart:convert';
import 'dart:developer';
import '../components/safetyZoneList.dart';
import 'dart:async';
import 'emergencyChatPage.dart';

String formatPlaceType(String type) {
  switch (type) {
    case 'police':
      return 'Police';
    case 'hospital':
      return 'Hospital';
    case 'fire_station':
      return 'Fire Station';
    case 'pharmacy':
      return 'Pharmacy';
    case 'doctor':
      return 'Doctor';
    default:
      return 'Unknown';
  }
}

class SafetyZoneMapScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String userState;
  final String emergencyType;

  SafetyZoneMapScreen(
      {Key? key,
      required this.userId,
      required this.userName,
      required this.userState,
      required this.emergencyType})
      : super(key: key);

  @override
  _SafetyZoneMapScreenState createState() => _SafetyZoneMapScreenState();
}

class _SafetyZoneMapScreenState extends State<SafetyZoneMapScreen> {
  StreamSubscription<Position>? _currentPositionSubscription;
  LatLng? _selectedSafetyZone;
  List<SafetyZone> _nearestSafetyZones = [];
  Position? _currentPosition;

  bool _isLoading = true;

  String _userId = '';
  String _userName = '';
  String _userState = '';
  String _emergencyType = '';

  final String placeAPIKey = "YOUR_API_KEY";

  @override
  void initState() {
    super.initState();
    _userId = widget.userId;
    _userName = widget.userName;
    _userState = widget.userState;
    _emergencyType = widget.emergencyType;
    _refreshLocation();
  }

  Future<void> _refreshLocation() async {
    try {
      Position? position = await getUserLocation(_userId);
        setState(() {
          _currentPosition = position;
          _fetchNearbySafetyPlaces();
        });
    } catch (e) {
      log('Error getting current location: $e');
      setState(() {
        _isLoading = false;
      });
      return;
    }
  }
  

  void _navigateToGoogleMaps(SafetyZone zone) async {
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
        _nearestSafetyZones = places;
        _isLoading = false;
      });
    } catch (e) {
      log('Error fetching safety places: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<List<SafetyZone>> _fetchPlacesByType(List<String> placeTypes) async {
    if (_currentPosition == null) return [];

    List<SafetyZone> result = [];

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
          final location = LatLng(
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
            SafetyZone(
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

  void _selectSafetyZone(SafetyZone zone) {
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

  Widget _buildPlaceDetails(SafetyZone zone) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                getIconForType(zone.type),
                color: getTypeColor(zone.type),
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
                  color: getTypeColor(zone.type),
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
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _navigateToGoogleMaps(zone),
              icon: const Icon(Icons.directions),
              label: const Text('Navigate', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: getTypeColor(zone.type),
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
                foregroundColor: getTypeColor(zone.type),
                side: BorderSide(color: getTypeColor(zone.type)),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _makePhoneCall(String phoneNumber) async {
    var flag = await makePhoneCall(phoneNumber);
    if (flag == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch phone call')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("Nearby Safety Places"),
          backgroundColor: Colors.red,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshLocation,
              tooltip: 'Refresh safety places',
            ),
          ],
        ),
        body:RefreshIndicator(onRefresh: _refreshLocation, child:  Builder(
          builder: (context) {
            log("Current location:" + _currentPosition.toString());

            // If location is still loading, show progress indicator
            if (_currentPosition == null) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      "Waiting for location data...",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }
            // If we have location but places are loading, show loading indicator
            else if (_isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            // If we have location and finished loading but no places found
            else if (_nearestSafetyZones.isEmpty) {
              return const Center(
                child: Text(
                  "No safety places found nearby.\nTry refreshing or expanding your search.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              );
            }

            // If we have location and safety places, show the list
            return SafetyPlacesList(
              safetyZones: _nearestSafetyZones,
              onPlaceSelected: _selectSafetyZone,
              selectedZoneLocation: _selectedSafetyZone,
            );
          },
        ),
        ),
        );
  }

  @override
  void dispose() {
    _currentPositionSubscription?.cancel();
    super.dispose();
  }
}
