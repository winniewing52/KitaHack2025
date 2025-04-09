import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../components/utils.dart';
import 'dart:developer' as dev;
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';

Widget crimeIcon(String crimeType) {
  IconData iconData;
  Color iconColor;
  switch (crimeType) {
    case "Harassment":
      iconData = Icons.warning;
      iconColor = Colors.orange;
      break;
    case "Sexual Assault":
      iconData = Icons.report;
      iconColor = Colors.red;
      break;
    case "Stalking":
      iconData = Icons.visibility;
      iconColor = Colors.purple;
      break;
    case "Theft":
      iconData = Icons.money_off;
      iconColor = Colors.blue;
      break;
    case "Kidnapping":
      iconData = Icons.lock;
      iconColor = Colors.black;
      break;
    case "Verbal Abuse":
      iconData = Icons.record_voice_over;
      iconColor = Colors.green;
      break;
    case "Unwanted Touching":
      iconData = Icons.pan_tool;
      iconColor = Colors.brown;
      break;
    default:
      iconData = Icons.error;
      iconColor = Colors.grey;
  }
  return Icon(iconData, color: iconColor, size: 30);
}

class CrimeMapScreen extends StatefulWidget {
  final String userId;

  const CrimeMapScreen({Key? key, required this.userId}) : super(key: key);

  @override
  _CrimeMapScreenState createState() => _CrimeMapScreenState();
}

class _CrimeMapScreenState extends State<CrimeMapScreen> {
  // Default center point and zoom level for the map
  double _currentZoom = 14.0;
  double _currentRadius = 5.0;
  Position? _currentPosition;
  List<Marker> _markers = [];

  // Controller to programmatically move the map
  final MapController _mapController = MapController();

  // User's current location

  final Map<double, double> _zoomRadiusMap = {
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
    _initCurrentLocation();
  }

  void _initCurrentLocation() async {
    try {
      Position? position = await getUserLocation(widget.userId);
      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      dev.log('Error getting current location: $e');
    }
  }

  // Shows an enhanced dialog with detailed crime information.
  void _showCrimeDetails(BuildContext context, Map<String, dynamic> crimeData, double distance) {
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
            _buildDetailRow(
                'Distance', '${distance.toStringAsFixed(0)}m'),
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

  // Helper to build detail rows with consistent styling
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

  Widget _buildMap() {
    if (_currentPosition == null) {
      return const Center(child: CircularProgressIndicator());
    }

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
      dev.log(_currentRadius.toString());
      // log("${documentList.length} crime records within $_currentRadius km");
      _markers.clear();
      _markers.add(
        Marker(
          point:
              LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
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
          var location = LatLng(data["location"]["geopoint"].latitude,
              data["location"]["geopoint"].longitude);

          // Calculate distance from the center to the crime location
          double distance = calculateStraightLineDistance(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              location.latitude,
              location.longitude);

          _markers.add(
            Marker(
              width: 40.0,
              height: 40.0,
              point: location,
              child: 
                  // Marker icon
                  GestureDetector(
                    onTap: () => _showCrimeDetails(context, data, distance),
                    child: crimeIcon(data['type'] ?? ''),
                  ),
            ),
          );
        }
      });
    });

    return FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          initialCenter: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          initialZoom: _currentZoom,
          onMapEvent: (event) {
            if (event is MapEventWithMove) {
              _onMapZoomChanged(event.camera.zoom);
            }
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          ),
          MarkerLayer(markers: _markers),
          // CircleLayer(
          //   circles: [
          //     CircleMarker(
          //         point: LatLng(
          //           _currentPosition!.latitude,
          //           _currentPosition!.longitude,
          //         ),
          //         radius: _currentRadius * 1000, // Convert km to meters
          //         color: Colors.blue.withOpacity(0.15),
          //         borderColor: Colors.blue.withOpacity(0.5),
          //         borderStrokeWidth: 2,
          //         useRadiusInMeter: true),
          //   ],
          // ),
        ]);
  }

  void _onMapZoomChanged(double zoom) {
    // Only update if zoom level has meaningfully changed
    if ((zoom - _currentZoom).abs() >= 0.5) {
      _currentZoom = zoom;
      // If the radius would change based on new zoom, update subscription
      double newRadius = _getRadiusForZoom(zoom);
      _currentRadius = newRadius;
      dev.log(_currentRadius.toString());
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text('Crime Map'),
          backgroundColor: Colors.red,
          actions: [
            IconButton(
              icon: Icon(Icons.my_location),
              onPressed: () {
                if (_currentPosition != null) {
                  _mapController.move(
                      LatLng(_currentPosition!.latitude,
                          _currentPosition!.longitude),
                      16);
                }
              },
            ),
          ],
        ),
        body: _buildMap());
  }
}
