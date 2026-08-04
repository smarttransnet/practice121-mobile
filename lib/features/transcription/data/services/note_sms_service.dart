import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';

class NoteSmsService {
  Future<void> sendPrescriptionSms({
    required Uri url,
    required String mobileNumber,
    required String body,
  }) async {
    try {
      AppLogger.i('Sending SMS request to: $url for $mobileNumber');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'mobileNumber': mobileNumber,
          'body': body,
        }),
      );

      if (response.statusCode != 200) {
        String message = 'SMS request failed (${response.statusCode}).';
        try {
          final errBody = jsonDecode(response.body);
          if (errBody is Map<String, dynamic> && errBody['error'] != null) {
            message = errBody['error'].toString();
          }
        } catch (_) {}
        throw UnexpectedFailure(message);
      }

      AppLogger.i('SMS request succeeded for $mobileNumber');
    } on Failure {
      rethrow;
    } catch (e, stack) {
      AppLogger.e('SMS sending failed', e, stack);
      throw UnexpectedFailure('Could not connect to SMS server: $e');
    }
  }
}
