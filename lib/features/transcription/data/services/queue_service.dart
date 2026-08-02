import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';

/// Response from the queue advance endpoint.
class NextPatientResponse {
  const NextPatientResponse({
    this.completedPatient,
    this.activePatient,
    required this.remainingQueueCount,
    required this.hasNextPatient,
  });

  /// The patient whose consultation was just completed (may be null on first
  /// call if no active patient existed yet).
  final QueuePatient? completedPatient;

  /// The patient who is now IN CONSULTATION, or null if the queue is empty.
  final QueuePatient? activePatient;

  /// How many patients are still waiting after this advance.
  final int remainingQueueCount;

  /// Whether a next patient was found and set active.
  final bool hasNextPatient;

  factory NextPatientResponse.fromJson(Map<String, dynamic> json) {
    return NextPatientResponse(
      completedPatient: json['completedPatient'] != null
          ? QueuePatient.fromJson(
              json['completedPatient'] as Map<String, dynamic>)
          : null,
      activePatient: json['activePatient'] != null
          ? QueuePatient.fromJson(
              json['activePatient'] as Map<String, dynamic>)
          : null,
      remainingQueueCount: (json['remainingQueueCount'] as num?)?.toInt() ?? 0,
      hasNextPatient: json['hasNextPatient'] as bool? ?? false,
    );
  }
}

/// Lightweight representation of a patient queue ticket.
class QueuePatient {
  const QueuePatient({
    required this.id,
    required this.queueNumber,
    required this.patientName,
    required this.patientMobile,
  });

  final String id;
  final int queueNumber;
  final String patientName;
  final String patientMobile;

  factory QueuePatient.fromJson(Map<String, dynamic> json) {
    return QueuePatient(
      id: json['id']?.toString() ?? '',
      queueNumber: (json['queueNumber'] as num?)?.toInt() ?? 0,
      patientName: json['patientName']?.toString() ?? 'Unknown',
      patientMobile: json['patientMobile']?.toString() ?? '',
    );
  }
}

/// Calls the Client-API to advance the queue to the next patient.
///
/// Mirrors the WEB `QueueService.js → advanceNextPatient()` function.
class QueueService {
  /// Base URL of the Practice121 Client-API.
  /// Matches the URL used in [httpClient.ts] in the web frontend.
  static const String _baseUrl =
      'https://practice121-api-687271578749.asia-southeast1.run.app';

  /// Marks the current active consultation as complete and activates the next
  /// waiting patient in the queue.
  ///
  /// [doctorId] is required. [practiceCentreId] and [visitDate] are optional
  /// but strongly recommended for accurate queue scoping.
  Future<NextPatientResponse> advanceNextPatient({
    required String doctorId,
    String? practiceCentreId,
    String? visitDate,
  }) async {
    if (doctorId.trim().isEmpty) {
      throw const UnexpectedFailure(
          'Doctor ID is required for queue progression.');
    }

    final uri = Uri.parse('$_baseUrl/api/v1/queue/next-patient');

    AppLogger.i(
        'QueueService: advancing next patient — doctorId=$doctorId, '
        'practiceCentreId=$practiceCentreId, visitDate=$visitDate');

    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'doctorId': doctorId,
          'practiceCentreId': practiceCentreId,
          'visitDate': visitDate,
        }),
      );

      if (response.statusCode != 200) {
        String message =
            'Queue transition failed (${response.statusCode}).';
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
          // ignore JSON parse errors on error bodies
        }
        AppLogger.e('QueueService: $message');
        throw UnexpectedFailure(message);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final result = NextPatientResponse.fromJson(data);

      AppLogger.i(
          'QueueService: advance succeeded — '
          'hasNext=${result.hasNextPatient}, '
          'activePatient=${result.activePatient?.patientName}, '
          'remaining=${result.remainingQueueCount}');

      return result;
    } on Failure {
      rethrow;
    } catch (e, stack) {
      AppLogger.e('QueueService: unexpected error', e, stack);
      throw UnexpectedFailure('Could not reach the queue server: $e');
    }
  }
}
