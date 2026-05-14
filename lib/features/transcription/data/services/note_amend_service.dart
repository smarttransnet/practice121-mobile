import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';

class NoteAmendService {
  Future<String> amendClinicalNote({
    required Uri url,
    required String originalNote,
    required String command,
    String? modelName,
  }) async {
    if (originalNote.trim().isEmpty) {
      throw const UnexpectedFailure('Original note is required.');
    }
    if (command.trim().isEmpty) {
      throw const UnexpectedFailure('Amendment command is required.');
    }

    try {
      AppLogger.i('Sending amendment request to: $url');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'originalNote': originalNote,
          'command': command,
          'modelName': modelName?.trim(),
        }),
      );

      if (response.statusCode != 200) {
        String message = 'Amend request failed (${response.statusCode}).';
        try {
          final errBody = jsonDecode(response.body);
          if (errBody is Map<String, dynamic>) {
            if (errBody['error'] != null) {
              message = errBody['error'].toString();
            } else if (errBody['detail'] != null) {
              message = errBody['detail'].toString();
            }
          }
        } catch (_) {
          // ignore parsing error
        }
        throw UnexpectedFailure(message);
      }

      final data = jsonDecode(response.body);
      final amendedNote = data['amendedNote'] as String?;
      if (amendedNote == null || amendedNote.isEmpty) {
        throw const UnexpectedFailure('Server returned an empty amended note.');
      }
      return amendedNote;
    } on Failure {
      rethrow;
    } catch (e, stack) {
      AppLogger.e('Amendment failed', e, stack);
      throw UnexpectedFailure('Could not connect to amend server: $e');
    }
  }
}
