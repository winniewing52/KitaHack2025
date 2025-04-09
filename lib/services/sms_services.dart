import 'package:twilio_flutter/twilio_flutter.dart';
import 'dart:developer';

class TwilioService {
  static final TwilioFlutter _twilioFlutter = TwilioFlutter(
    accountSid: 'YOUR_ACCOUNT_SID',
    authToken: 'YOUR_AUTH_TOKEN', 
    twilioNumber: 'YOUR_TWILIO_NUMBER' 
  );

  static Future<bool> sendEmergencySMS(String to, String message) async {
    try {
      await _twilioFlutter.sendSMS(
        toNumber: to,
        messageBody: message
      );
      return true;
    } catch (e) {
      log('Error sending SMS: $e');
      return false;
    }
  }
}