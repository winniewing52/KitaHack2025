import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:safety_of_sisters/components/utils.dart';
import 'dart:developer';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'dart:async';
import '../components/emergencyUserList.dart';
import 'emergencyChatPage.dart';

class NearbyEmergencyUsersScreen extends StatefulWidget {
  final String currentUserId;

  const NearbyEmergencyUsersScreen({Key? key, required this.currentUserId})
      : super(key: key);

  @override
  _NearbyEmergencyUsersScreenState createState() =>
      _NearbyEmergencyUsersScreenState();
}

class _NearbyEmergencyUsersScreenState
    extends State<NearbyEmergencyUsersScreen> {
  Position? _currentPosition;
  StreamSubscription<Position>? _currentPositionSubscription;

  List<EmergencyUser> _nearbyEmergencyUsers = [];
  Stream<List<EmergencyUser>>? _emergencyUsersStream;
  EmergencyUser? _selectedEmergencyUser;
  StreamSubscription<List<EmergencyUser>>? _emergencyUsersSubscription;

  Timer? _helpStatusCheckTimer;
  StreamSubscription<QuerySnapshot>? _chatStreamSubscription;

  bool _isLoading = true;
  bool _isHelpingAnyone = false;
  String? _currentUserId;
  String? _helpingUserId;
  EmergencyUser? _helpingUser;

  @override
  void initState() {
    super.initState();
    _currentUserId = widget.currentUserId;
    // _checkHelpingStatus();
    _initHelpingStatus();
    _getLocation();
    // Set up periodic help status check
    // _helpStatusCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) {
    //   _checkHelpingStatus();
    // });
    _initChatNotifications();
  }

  Future<void> _getLocation() async {
    try {
      Position? position = await getUserLocation(_currentUserId!);
      setState(() {
        _currentPosition = position;
        _startStreamingNearbyEmergencyUsers();
      });
    } catch (e) {
      log('Error getting current location: $e');
      setState(() {
        _isLoading = false;
      });
      return;
    }
  }

  void _initHelpingStatus() async {
    try {
      DocumentSnapshot curUserData =
          await usersCollection.doc(_currentUserId!).get();
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
        final helpedUser = EmergencyUser(
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
    } catch (e) {
      log('Error checking helping status: $e');
    }
  }

  void _initChatNotifications() {
    final chatRef = FirebaseFirestore.instance
        .collection('emergency_group_chats')
        .doc('emergency_$_helpingUserId')
        .collection('messages');

    _chatStreamSubscription = chatRef
        .where('senderId',
            isNotEqualTo: _currentUserId) // Don't count own messages
        .where('isRead', isEqualTo: false) // Only unread messages
        .snapshots()
        .listen((snapshot) {
      setState(() {});
    });
  }

  // Future<void> _checkHelpingStatus() async {
  //   if (_currentUserId == null) return;

  //   try {
  //     QuerySnapshot helpingQuery = await usersCollection
  //         .where('helpersOnTheWay', arrayContains: _currentUserId)
  //         .where('status', isEqualTo: 'emergency')
  //         .get();

  //     if (helpingQuery.docs.isNotEmpty) {
  //       final helpedUserDoc = helpingQuery.docs.first;
  //       final helpedUserData = helpedUserDoc.data() as Map<String, dynamic>;

  //       // Extract GeoPoint from the position data
  //       GeoPoint geoPoint = helpedUserData['position']['geopoint'];

  //       // Calculate distance if current position is available
  //       double distance = 0;
  //       if (_currentPosition != null) {
  //         distance = calculateStraightLineDistance(
  //             _currentPosition!.latitude,
  //             _currentPosition!.longitude,
  //             geoPoint.latitude,
  //             geoPoint.longitude);
  //       }

  //       // Create EmergencyUser object for the user being helped
  //       final helpedUser = EmergencyUser(
  //         id: helpedUserDoc.id,
  //         name: helpedUserData['username'],
  //         phoneNumber: helpedUserData['handphone'],
  //         location: geoPoint,
  //         distance: distance,
  //         helpersCount: helpedUserData['helpersCount'] ?? 0,
  //         helpersOnTheWay: List<String>.from(
  //           helpedUserData['helpersOnTheWay'] ?? [],
  //         ),
  //         emergencyType: helpedUserData['emergencyType'] ?? 'Unknown',
  //         timestamp: (helpedUserData['emergencyAt']).toDate(),
  //       );

  //       setState(() {
  //         _isHelpingAnyone = true;
  //         _helpingUserId = helpedUserDoc.id;
  //         _helpingUser = helpedUser;
  //       });
  //     } else {
  //       setState(() {
  //         _isHelpingAnyone = false;
  //         _helpingUserId = null;
  //         _helpingUser = null;
  //       });
  //     }
  //   } catch (e) {
  //     log('Error checking helping status: $e');
  //   }
  // }

  void _startStreamingNearbyEmergencyUsers() async {
    try {
      Position? position = await getUserLocation(_currentUserId!);
      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      log('Error getting current location: $e');
      _isLoading = false;
      return;
    }

    final center = GeoFirePoint(
        GeoPoint(_currentPosition!.latitude, _currentPosition!.longitude));

    // Get nearby users within 10km
    double radiusInKm = 10.0;

    // Use subscribeWithin from geoflutterfire_plus on the users collection
    _emergencyUsersStream = GeoCollectionReference(
            usersCollection as CollectionReference<Map<String, dynamic>>)
        .subscribeWithin(
            center: center,
            radiusInKm: radiusInKm,
            field: 'position',
            geopointFrom: (data) {
              return data['position']['geopoint'] as GeoPoint;
            })
        .map((List<DocumentSnapshot<Map<String, dynamic>>> documentList) {
      setState(() {
        _isLoading = false;
      });
      List<EmergencyUser> emergencyUsers = [];

      // Use for loop to filter only users with emergency status
      for (var document in documentList) {
        Map<String, dynamic> data = document.data() as Map<String, dynamic>;
        // Check if user has emergency status
        if (document.id != _currentUserId &&
            data["status"] != null &&
            data['status'] == 'emergency') {
          // Extract GeoPoint from the position data
          GeoPoint geoPoint = data['position']['geopoint'];

          // Calculate distance from current user
          double distance = calculateStraightLineDistance(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              geoPoint.latitude,
              geoPoint.longitude);

          emergencyUsers.add(
            EmergencyUser(
              id: document.id,
              name: data['username'],
              phoneNumber: data['handphone'],
              location: geoPoint,
              distance: distance,
              helpersCount: data['helpersCount'] ?? 0,
              helpersOnTheWay: List<String>.from(
                data['helpersOnTheWay'] ?? [],
              ),
              // User choice or SOS by default
              emergencyType: data['emergencyType'],
              timestamp: (data['emergencyAt']).toDate(),
            ),
          );
        }
      }

      return emergencyUsers;
    });

    // Subscribe to the stream
    _emergencyUsersSubscription =
        _emergencyUsersStream!.listen((emergencyUsers) {
      setState(() {
        _nearbyEmergencyUsers = emergencyUsers;

        // Sort the list with helping user at top, then by distance
        _nearbyEmergencyUsers.sort((a, b) {
          // If user a is the one being helped, it should come first
          if (_isHelpingAnyone && a.id == _helpingUserId) {
            return -1;
          }
          // If user b is the one being helped, it should come first
          if (_isHelpingAnyone && b.id == _helpingUserId) {
            return 1;
          }
          // Otherwise sort by distance
          return a.distance.compareTo(b.distance);
        });

        // Update the helping user (EmergencyUser Object) if it exists in the new list
        if (_isHelpingAnyone && _helpingUserId != null) {
          for (var user in _nearbyEmergencyUsers) {
            if (user.id == _helpingUserId) {
              _helpingUser = user;
              break;
            }
          }
        }
      });
    });
  }

  void _openChat(EmergencyUser emergencyUser) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmergencyGroupChatScreen(
          currentUserId: _currentUserId!,
          emergencyUserId: emergencyUser.id,
          emergencyUserName: emergencyUser.name,
          emergencyType: emergencyUser.emergencyType,
        ),
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

  void _navigateToGoogleMaps(EmergencyUser emergencyUser) async {
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

  void _selectEmergencyUser(EmergencyUser emergencyUser) {
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

  Future<void> _offerHelp(EmergencyUser emergencyUser) async {
    if (_currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need to be logged in to offer help')),
      );
      return;
    }

    try {
      DocumentReference emergencyUserRef =
          usersCollection.doc(emergencyUser.id);

      if (emergencyUser.helpersOnTheWay.contains(_currentUserId)) {
        // Cancel help
        _cancelHelp();
      } else {
        // Offer help
        if (_isHelpingAnyone) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You are already helping someone else'),
            ),
          );
          return;
        }

        await emergencyUserRef.update({
          'helpersOnTheWay': FieldValue.arrayUnion([_currentUserId]),
          'helpersCount': FieldValue.increment(1),
        });

        usersCollection
            .doc(_currentUserId)
            .set({'helpingUserId': emergencyUser.id}, SetOptions(merge: true));

        // Update helping status
        setState(() {
          _isHelpingAnyone = true;
          _helpingUserId = emergencyUser.id;
          _helpingUser = emergencyUser;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are now helping this person')),
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
        'helpersOnTheWay': FieldValue.arrayRemove([_currentUserId]),
        'helpersCount': FieldValue.increment(-1),
      });

      usersCollection
          .doc(_currentUserId)
          .set({'helpingUserId': null}, SetOptions(merge: true));

      setState(() {
        _isHelpingAnyone = false;
        _helpingUserId = null;
        _helpingUser = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are no longer helping this person')),
      );
    } catch (e) {
      log('Error canceling help: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to cancel help')));
    }
  }

  Widget _buildUserDetails(EmergencyUser emergencyUser) {
    bool isHelping = _currentUserId != null &&
        emergencyUser.helpersOnTheWay.contains(_currentUserId);
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
                  getIconForType(emergencyUser.emergencyType),
                  color: getTypeColor(emergencyUser.emergencyType),
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
                    color: getTypeColor(emergencyUser.emergencyType),
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
                  'Emergency reported: ${formatTimestampEmergency(emergencyUser.timestamp)}',
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
                onPressed: () => _navigateToGoogleMaps(emergencyUser),
                icon: const Icon(Icons.directions),
                label: const Text('Navigate', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: getTypeColor(emergencyUser.emergencyType),
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
                      _openChat(emergencyUser);
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
            getIconForType(_helpingUser!.emergencyType),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Nearby Emergency Users"),
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _getLocation,
            tooltip: 'Refresh emergency users',
          ),
          if (_isHelpingAnyone && _helpingUser != null)
            IconButton(
              icon: const Icon(Icons.chat),
              onPressed: () => _openChat(_helpingUser!),
              tooltip: 'Chat with person you are helping',
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _getLocation,
        child: Column(
          children: [
            _buildHelpingBanner(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _nearbyEmergencyUsers.isEmpty
                      ? const Center(
                          child: Text(
                            "No emergency users found nearby.\nTry refreshing or expanding your search.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : EmergencyUsersList(
                          emergencyUsers: _nearbyEmergencyUsers,
                          onUserSelected: _selectEmergencyUser,
                          selectedUser: _selectedEmergencyUser,
                          currentUserId: _currentUserId,
                          isHelpingAnyone: _isHelpingAnyone,
                          helpingUserId: _helpingUserId,
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _nearbyEmergencyUsers.isNotEmpty &&
              (!_isHelpingAnyone ||
                  (_helpingUserId != null &&
                      _helpingUserId == _nearbyEmergencyUsers.first.id))
          ? FloatingActionButton.extended(
              onPressed: () {
                _navigateToGoogleMaps(_nearbyEmergencyUsers.first);
              },
              icon: const Icon(Icons.sos),
              label: const Text('Closest Emergency'),
              backgroundColor: const Color.fromARGB(255, 232, 95, 85),
            )
          : null,
    );
  }

  @override
  void dispose() {
    _chatStreamSubscription?.cancel();
    _emergencyUsersSubscription?.cancel();
    _currentPositionSubscription?.cancel();
    _helpStatusCheckTimer?.cancel();
    super.dispose();
  }
}
