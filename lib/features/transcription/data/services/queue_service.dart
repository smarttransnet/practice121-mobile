import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';

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

/// Detailed patient queue ticket for the Patient Queue Screen.
class QueueTicket {
  const QueueTicket({
    required this.id,
    required this.queueNumber,
    required this.patientName,
    required this.patientMobile,
    required this.status, // 0: Waiting, 1: Ready, 2: Called, 3: In Consultation, 4: Completed, 5: Cancelled
    required this.priority, // 0: Normal, 1: High, 2: Emergency
    this.sessionName,
  });

  final String id;
  final int queueNumber;
  final String patientName;
  final String patientMobile;
  final int status;
  final int priority;
  final String? sessionName;

  factory QueueTicket.fromJson(Map<String, dynamic> json) {
    return QueueTicket(
      id: json['id']?.toString() ?? '',
      queueNumber: (json['queueNumber'] as num?)?.toInt() ?? (json['queueOrder'] as num?)?.toInt() ?? 1,
      patientName: json['patientName']?.toString() ?? 'Patient',
      patientMobile: json['patientMobile']?.toString() ?? '',
      status: (json['status'] as num?)?.toInt() ?? 0,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      sessionName: json['sessionName']?.toString() ?? json['sessionLabel']?.toString(),
    );
  }
}

/// Calls the Client-API to advance the queue to the next patient.
class QueueService {
  QueueService({ApiClient? apiClient}) : _apiClient = apiClient;

  final ApiClient? _apiClient;

  /// Base URL of the Practice121 Client-API.
  static const String _baseUrl =
      'https://practice121-api-687271578749.asia-southeast1.run.app';

  /// Fetches active queue tickets for the selected practice centre.
  Future<List<QueueTicket>> fetchQueueTickets({
    required String practiceCentreId,
    String? doctorId,
    String? visitDate,
  }) async {
    final queryParams = <String, String>{
      'practiceCentreId': practiceCentreId,
      if (doctorId != null && doctorId.isNotEmpty) 'doctorId': doctorId,
      if (visitDate != null && visitDate.isNotEmpty) 'visitDate': visitDate,
    };
    final uri = Uri.parse('$_baseUrl/api/patient-queue')
        .replace(queryParameters: queryParams);

    try {
      final response = _apiClient != null
          ? await _apiClient.get(uri)
          : await http.get(uri);

      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body);
        return list.map((item) => QueueTicket.fromJson(item)).toList();
      }
      AppLogger.w('QueueService: fetch queue status code ${response.statusCode}');
      return [];
    } catch (e) {
      AppLogger.w('QueueService: fetch queue tickets failed: $e');
      return [];
    }
  }

  /// Updates ticket status (e.g. 3: In Consultation, 4: Completed).
  Future<bool> updateTicketStatus(String ticketId, int status) async {
    final uri = Uri.parse('$_baseUrl/api/patient-queue/$ticketId/status');
    try {
      final response = _apiClient != null
          ? await _apiClient.put(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'status': status}),
            )
          : await http.put(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'status': status}),
            );
      return response.statusCode == 200;
    } catch (e) {
      AppLogger.w('QueueService: update ticket status failed: $e');
      return false;
    }
  }

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
      final response = _apiClient != null
          ? await _apiClient.post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'doctorId': doctorId,
                'practiceCentreId': practiceCentreId,
                'visitDate': visitDate,
              }),
            )
          : await http.post(
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

  /// Adds a new patient queue ticket to the practice centre session queue.
  Future<String> addPatientQueueTicket({
    required String patientMobile,
    required String doctorId,
    required String practiceCentreId,
    required int priority,
    String? visitDate,
    String? patientId,
    String? sessionId,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/patient-queue');
    final sanitizedSessionId =
        (sessionId != null && sessionId != 'ALL' && sessionId.trim().isNotEmpty)
            ? sessionId
            : null;

    final bodyMap = <String, dynamic>{
      'patientMobile': patientMobile,
      'doctorId': doctorId,
      'practiceCentreId': practiceCentreId,
      'priority': priority,
    };
    if (visitDate != null && visitDate.isNotEmpty) bodyMap['visitDate'] = visitDate;
    if (patientId != null && patientId.isNotEmpty) bodyMap['patientId'] = patientId;
    if (sanitizedSessionId != null) bodyMap['sessionId'] = sanitizedSessionId;

    try {
      final response = _apiClient != null
          ? await _apiClient.post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(bodyMap),
            )
          : await http.post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(bodyMap),
            );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.body.replaceAll('"', '');
      }

      String message = 'Failed to add patient to queue (${response.statusCode}).';
      try {
        final errBody = jsonDecode(response.body);
        if (errBody is Map<String, dynamic>) {
          if (errBody['detail'] != null) {
            message = errBody['detail'].toString();
          } else if (errBody['error'] != null) {
            message = errBody['error'].toString();
          } else if (errBody['message'] != null) {
            message = errBody['message'].toString();
          }
        }
      } catch (_) {}
      throw UnexpectedFailure(message);
    } on Failure {
      rethrow;
    } catch (e) {
      throw UnexpectedFailure('Could not add patient to queue: $e');
    }
  }
}

