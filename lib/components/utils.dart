import 'package:geolocator/geolocator.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:another_telephony/telephony.dart';
import 'dart:developer';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

final CollectionReference usersCollection =
    FirebaseFirestore.instance.collection('users');
final CollectionReference emergencyChatRoom =
    FirebaseFirestore.instance.collection('emergency_group_chats');
final CollectionReference crimeCollection = 
  FirebaseFirestore.instance.collection('crimes_history');

final Telephony telephony = Telephony.instance;

LocationSettings locationSettings = AndroidSettings(
  accuracy: LocationAccuracy.best,
  forceLocationManager: true,
  distanceFilter: 100,
  intervalDuration: const Duration(seconds: 3),
  foregroundNotificationConfig: const ForegroundNotificationConfig(
    notificationText:
        "Safety Of Sisters will continue to receive your location even when you aren't using it",
    notificationTitle: "Tracking",
    setOngoing: true,
    enableWakeLock: true,
  ),
);

double calculateStraightLineDistance(
    double lat_1, double log_1, double lat_2, double log_2) {
  return Geolocator.distanceBetween(lat_1, log_1, lat_2, log_2);
}

void updateUserLocation(String userId, Position position) {
  GeoFirePoint geoPoint = GeoFirePoint(
    GeoPoint(position.latitude, position.longitude),
  );
  usersCollection.doc(userId).set({
    'position': geoPoint.data,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<Position?> getUserLocation(String userId) async {
  try {
    DocumentSnapshot userDoc = await usersCollection.doc(userId).get();

    if (!userDoc.exists) {
      return null;
    }

    Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
    GeoPoint g = userData['position']["geopoint"];
    return Position(
      latitude: g.latitude,
      longitude: g.longitude,
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      accuracy: 0.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      altitudeAccuracy: 0.0,
      headingAccuracy: 0.0,
    );
  } catch (e) {
    log(e.toString());
    return null;
  }
}

String formatTimestamp(Timestamp? timestamp) {
  if (timestamp == null) return '';

  DateTime messageTime = timestamp.toDate();
  DateTime now = DateTime.now();

  if (now.difference(messageTime).inDays == 0) {
    // Today, show time only
    return DateFormat.jm().format(messageTime);
  } else if (now.difference(messageTime).inDays == 1) {
    // Yesterday
    return 'Yesterday ${DateFormat.jm().format(messageTime)}';
  } else {
    // Other days, show date and time
    return DateFormat('MMM d, h:mm a').format(messageTime);
  }
}

Future<bool> navigateToGoogleMaps(
    double curLat, double curLong, double desLat, double desLong) async {
  final url =
      'https://www.google.com/maps/dir/?api=1&origin=${curLat},${curLong}&destination=${desLat},${desLong}&travelmode=walking';

  final Uri launchUri = Uri.parse(url);
  try {
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
      return true;
    } else {
      return false;
    }
  } catch (e) {
    log('Error launching map: $e');
    return false;
  }
}

  Future<bool> makePhoneCall(String phoneNumber) async {
    if (phoneNumber == "Not available") {
      return false;
    }

    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);

    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
        return true;
      } else {
        return false;
      }
    } catch (e) {
      log('Error making phone call: $e');
      return false;
    }
  }
