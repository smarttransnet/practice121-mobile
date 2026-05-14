import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';

class NoteEmailService {
  Future<void> sendClinicalNoteEmail({
    required Uri url,
    required String toEmail,
    required String subject,
    required String body,
  }) async {
    try {
      AppLogger.i('Sending email request to: $url for $toEmail');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'toEmail': toEmail,
          'subject': subject,
          'body': body,
        }),
      );

      if (response.statusCode != 200) {
        String message = 'Email request failed (${response.statusCode}).';
        try {
          final errBody = jsonDecode(response.body);
          if (errBody is Map<String, dynamic> && errBody['error'] != null) {
            message = errBody['error'].toString();
          }
        } catch (_) {}
        throw UnexpectedFailure(message);
      }

      AppLogger.i('Email request succeeded for $toEmail');
    } on Failure {
      rethrow;
    } catch (e, stack) {
      AppLogger.e('Email sending failed', e, stack);
      throw UnexpectedFailure('Could not connect to email server: $e');
    }
  }
}
