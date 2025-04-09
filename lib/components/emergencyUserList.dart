import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

String formatTimestampEmergency(DateTime timestamp) {
  DateTime now = DateTime.now();
  Duration difference = now.difference(timestamp);

  if (difference.inMinutes < 1) {
    return 'Just now';
  } else if (difference.inMinutes < 60) {
    return '${difference.inMinutes}m ago';
  } else if (difference.inHours < 24) {
    return '${difference.inHours}h ago';
  } else {
    return '${difference.inDays}d ago';
  }
}

Color getTypeColor(String type) {
  switch (type.toLowerCase()) {
    case 'medical':
      return Colors.red;
    case 'accident':
      return Colors.orange;
    case 'fire':
      return Colors.deepOrange;
    case 'crime':
      return Colors.blue;
    case 'natural disaster':
      return Colors.purple;
    default:
      return Colors.red;
  }
}

IconData getIconForType(String type) {
  switch (type.toLowerCase()) {
    case 'medical':
      return Icons.medical_services;
    case 'accident':
      return Icons.car_crash;
    case 'fire':
      return Icons.local_fire_department;
    case 'crime':
      return Icons.security;
    case 'natural disaster':
      return Icons.storm;
    default:
      return Icons.sos;
  }
}

class EmergencyUserCard extends StatelessWidget {
  final EmergencyUser emergencyUser;
  final Function(EmergencyUser) onUserSelected;
  final EmergencyUser? selectedUser;
  final String? currentUserId;
  final bool isHelpingAnyone;
  final String? helpingUserId;

    const EmergencyUserCard({
    Key? key,
    required this.emergencyUser,
    required this.onUserSelected,
    this.selectedUser,
    this.currentUserId,
    required this.isHelpingAnyone,
    this.helpingUserId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final user = emergencyUser;
        final bool isSelected =
            selectedUser != null && selectedUser!.id == user.id;
        final bool isHelping = currentUserId != null &&
            user.helpersOnTheWay.contains(currentUserId);
        final bool isDisabled = isHelpingAnyone && user.id != helpingUserId;

       return Card(
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),

          elevation: isSelected ? 4 : 1,
          color: isDisabled ? Colors.grey[200] : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isSelected
                ? BorderSide(color: getTypeColor(user.emergencyType), width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: isDisabled ? null : () => onUserSelected(user),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: getTypeColor(user.emergencyType)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          getIconForType(user.emergencyType),
                          color: getTypeColor(user.emergencyType),
                          size: 30,
                        ),
                      ),
                      if (isHelping)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.green, width: 2),
                            ),
                            child: const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Column(
                          children: [
                            Row(children:[Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: getTypeColor(user.emergencyType)
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                user.emergencyType,
                                style: TextStyle(
                                  color: getTypeColor(user.emergencyType),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            ]),
                            Row(children: [
                            Icon(
                              Icons.directions_walk,
                              size: 18,
                              color: Colors.grey[600],
                            ),
                            
                            const SizedBox(width: 4),
                            Text(
                              '${(user.distance / 1000).toStringAsFixed(2)} km',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 18,
                              ),
                            ),
                            ]),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.people,
                              size: 18,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${user.helpersCount} helpers',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.access_time,
                              size: 18,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatTimestampEmergency(user.timestamp),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () => onUserSelected(user),
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

class EmergencyUsersList extends StatelessWidget {
  final List<EmergencyUser> emergencyUsers;
  final Function(EmergencyUser) onUserSelected;
  final EmergencyUser? selectedUser;
  final String? currentUserId;
  final bool isHelpingAnyone;
  final String? helpingUserId;

  const EmergencyUsersList({
    Key? key,
    required this.emergencyUsers,
    required this.onUserSelected,
    this.selectedUser,
    this.currentUserId,
    required this.isHelpingAnyone,
    this.helpingUserId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: emergencyUsers.length,
      itemBuilder: (context, index) {
        final user = emergencyUsers[index];
        final bool isSelected =
            selectedUser != null && selectedUser!.id == user.id;
        final bool isHelping = currentUserId != null &&
            user.helpersOnTheWay.contains(currentUserId);
        final bool isDisabled = isHelpingAnyone && user.id != helpingUserId;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: isSelected ? 4 : 1,
          color: isDisabled ? Colors.grey[200] : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isSelected
                ? BorderSide(color: getTypeColor(user.emergencyType), width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: isDisabled ? null : () => onUserSelected(user),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: getTypeColor(user.emergencyType)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          getIconForType(user.emergencyType),
                          color: getTypeColor(user.emergencyType),
                          size: 30,
                        ),
                      ),
                      if (isHelping)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.green, width: 2),
                            ),
                            child: const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: 4),
                       Column(
                          children: [
                            Row(children:[Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: getTypeColor(user.emergencyType)
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                user.emergencyType,
                                style: TextStyle(
                                  color: getTypeColor(user.emergencyType),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            ]),
                            Row(children: [
                            Icon(
                              Icons.directions_walk,
                              size: 18,
                              color: Colors.grey[600],
                            ),
                            
                            const SizedBox(width: 4),
                            Text(
                              '${(user.distance / 1000).toStringAsFixed(2)} km',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 18,
                              ),
                            ),
                            ]),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.people,
                              size: 18,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${user.helpersCount} helpers',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.access_time,
                              size: 18,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatTimestampEmergency(user.timestamp),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () => onUserSelected(user),
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

class EmergencyUser {
  final String id;
  final String name;
  final String phoneNumber;
  final GeoPoint location;
  final double distance;
  final int helpersCount;
  final List<String> helpersOnTheWay;
  final String emergencyType;
  final DateTime timestamp;

  EmergencyUser({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.location,
    required this.distance,
    required this.helpersCount,
    required this.helpersOnTheWay,
    required this.emergencyType,
    required this.timestamp,
  });
}
