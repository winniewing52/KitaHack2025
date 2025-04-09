import 'package:flutter/material.dart';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../components/utils.dart';
import '../services/sms_services.dart';

class EmergencyContactManager {
  static Future<void> notifyEmergencyContacts(String currentUserId,
      String userName, String emergencyType, double lat, double lng) async {
    try {
      DocumentSnapshot<Map<String, dynamic>> userDoc = await usersCollection
          .doc(currentUserId)
          .get() as DocumentSnapshot<Map<String, dynamic>>;

      if (!userDoc.exists || !(userDoc.data()?['emergencyContacts'] != null)) {
        return;
      }

      List<dynamic> contacts = userDoc.data()!['emergencyContacts'];

      for (var contact in contacts) {
        String message = '''
          EMERGENCY ALERT FROM SAFETY-OF-SISTERS!
          $userName needs help!
          Type: $emergencyType
          Lat: ${lat.toStringAsFixed(6)}
          Lng: ${lng.toStringAsFixed(6)}
          ''';

        await TwilioService.sendEmergencySMS(contact['phone'], message);
      }
    } catch (e) {
      log('Error notifying emergency contacts: $e');
    }
  }

  static Future<bool> addContact(
    String currentUserId,
    String contactPhone,
    String contactName,
  ) async {
    try {
      // Validate phone number format
      final phoneRegExp = RegExp(r'^\+[1-9]\d{1,3}[-\s]?\(?[1-9]\d{1,4}\)?[-\s]?\d{1,4}[-\s]?\d{1,4}[-\s]?\d{1,9}$');
      if (!phoneRegExp.hasMatch(contactPhone)) {
        return false;
      }

      // Update the current user's emergency contacts
      await usersCollection.doc(currentUserId).update({
        'emergencyContacts': FieldValue.arrayUnion([
          {
            'phone': contactPhone,
            'name': contactName,
          }
        ])
      });

      return true;
    } catch (e) {
      log('Error adding contact: $e');
      return false;
    }
  }

  static Stream<List<Map<String, dynamic>>> getContactsStream(
      String currentUserId) {
    return usersCollection.doc(currentUserId).snapshots().map((userDoc) {
      var data = userDoc.data() as Map<String, dynamic>;
      if (!userDoc.exists || !(data['emergencyContacts'] != null)) {
        return [];
      }

      List<dynamic> contacts = data['emergencyContacts'];
      return contacts
          .map((contact) => Map<String, dynamic>.from(contact))
          .toList();
    });
  }

  static Future<bool> removeContact(
      String currentUserId, String contactPhone) async {
    try {
      DocumentSnapshot<Map<String, dynamic>> userDoc = await usersCollection
          .doc(currentUserId)
          .get() as DocumentSnapshot<Map<String, dynamic>>;

      if (!userDoc.exists || !(userDoc.data()?['emergencyContacts'] != null)) {
        return false;
      }

      List<dynamic> contacts = List.from(userDoc.data()!['emergencyContacts']);
      contacts.removeWhere((contact) => contact['phone'] == contactPhone);

      await usersCollection
          .doc(currentUserId)
          .update({'emergencyContacts': contacts});

      return true;
    } catch (e) {
      log('Error removing contact: $e');
      return false;
    }
  }
}

class EmergencyContactsScreen extends StatefulWidget {
  final String currentUserId;

  const EmergencyContactsScreen({Key? key, required this.currentUserId})
      : super(key: key);

  @override
  _EmergencyContactsScreenState createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Emergency Contacts'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Contact Name',
                    hintText: 'Enter contact name',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _phoneController,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    hintText: 'Enter phone number with country code',
                    border: OutlineInputBorder(),
                    prefixText: '+',
                  ),
                  keyboardType: TextInputType.phone,
                ),
                SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (_phoneController.text.isNotEmpty &&
                        _nameController.text.isNotEmpty) {
                      final added = await EmergencyContactManager.addContact(
                        widget.currentUserId,
                        '+${_phoneController.text.trim()}',
                        _nameController.text.trim(),
                      );

                      if (added) {
                        _phoneController.clear();
                        _nameController.clear();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Contact added successfully')));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              'Invalid phone number format. Use international format (e.g., +1234567890)'),
                          backgroundColor: Colors.red,
                        ));
                      }
                    }
                  },
                  child: Text('Add Contact'),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: EmergencyContactManager.getContactsStream(
                  widget.currentUserId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }

                final contacts = snapshot.data!;

                return ListView.builder(
                  itemCount: contacts.length,
                  itemBuilder: (context, index) {
                    final contact = contacts[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(contact['name'][0].toUpperCase()),
                      ),
                      title: Text(contact['name']),
                      subtitle: Text(
                        contact['phone'],
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.delete),
                        onPressed: () async {
                          await EmergencyContactManager.removeContact(
                            widget.currentUserId,
                            contact['phone'],
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
