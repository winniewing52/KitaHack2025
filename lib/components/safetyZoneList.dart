import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Color getTypeColor(String type) {
  switch (type.toLowerCase()) {
    case 'police':
      return Colors.blue;
    case 'hospital':
      return Colors.red;
    case 'pharmacy':
      return Colors.pink;
    case 'doctor':
      return Colors.red;
    case 'fire station':
      return Colors.orange;
    default:
      return Colors.orange;
  }
}

IconData getIconForType(String type) {
  switch (type.toLowerCase()) {
    case 'police':
      return Icons.local_police;
    case 'hospital':
      return Icons.local_hospital;
    case 'fire station':
      return Icons.fire_extinguisher;
    case 'pharmacy':
      return Icons.local_pharmacy;
    case 'doctor':
      return Icons.medical_services;
    default:
      return Icons.location_city;
  }
}

class SafetyPlaceCard extends StatelessWidget {
  final SafetyZone safetyZone;
  final Function(SafetyZone) onPlaceSelected;
  final LatLng? selectedZoneLocation;
    const SafetyPlaceCard({
    Key? key,
    required this.safetyZone,
    required this.onPlaceSelected,
    this.selectedZoneLocation,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
        final zone = safetyZone;
        final bool isSelected = selectedZoneLocation != null &&
            selectedZoneLocation!.latitude == zone.location.latitude &&
            selectedZoneLocation!.longitude == zone.location.longitude;

        return Card(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),

          elevation: isSelected ? 4 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isSelected
                ? BorderSide(color: getTypeColor(zone.type), width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: () => onPlaceSelected(zone),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: getTypeColor(zone.type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      getIconForType(zone.type),
                      color: getTypeColor(zone.type),
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          zone.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    getTypeColor(zone.type).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                zone.type,
                                style: TextStyle(
                                  color: getTypeColor(zone.type),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                                               TextButton.icon(
                              onPressed: () => onPlaceSelected(zone),
                              icon: const Icon(Icons.info_outline, size: 16),
                              label: const Text('Details'),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
        
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      
  }
}

class SafetyPlacesList extends StatelessWidget {
  final List<SafetyZone> safetyZones;
  final Function(SafetyZone) onPlaceSelected;
  final LatLng? selectedZoneLocation;

  const SafetyPlacesList({
    Key? key,
    required this.safetyZones,
    required this.onPlaceSelected,
    this.selectedZoneLocation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: safetyZones.length,
      itemBuilder: (context, index) {
        final zone = safetyZones[index];
        final bool isSelected = selectedZoneLocation != null &&
            selectedZoneLocation!.latitude == zone.location.latitude &&
            selectedZoneLocation!.longitude == zone.location.longitude;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: isSelected ? 4 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isSelected
                ? BorderSide(color: getTypeColor(zone.type), width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: () => onPlaceSelected(zone),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: getTypeColor(zone.type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      getIconForType(zone.type),
                      color: getTypeColor(zone.type),
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          zone.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    getTypeColor(zone.type).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                zone.type,
                                style: TextStyle(
                                  color: getTypeColor(zone.type),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.directions_walk,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${(zone.distance / 1000).toStringAsFixed(2)} km',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          zone.address,
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () => onPlaceSelected(zone),
                              icon: const Icon(Icons.info_outline, size: 16),
                              label: const Text('Details'),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class SafetyZone {
  final String id;
  final String name;
  final String address;
  final String type; // e.g., Police, Hospital, Pharmacy, etc.
  final LatLng location;
  double distance = 0; // Straight-line distance
  final String phoneNumber;

  SafetyZone({
    required this.id,
    required this.name,
    required this.address,
    required this.type,
    required this.location,
    required this.phoneNumber,
  });
}
