import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../models/practice_centre.dart';

/// Fetches practice centres and patient queue stats from Client-API.
class PracticeCentreService {
  /// Retrieves all practice centres assigned to the authenticated doctor.
  Future<List<PracticeCentre>> getDoctorPracticeCentres({
    required String baseUrl,
    required String accessToken,
  }) async {
    final uri = Uri.parse('$baseUrl/api/practice-centres');
    AppLogger.i('PracticeCentreService: fetching centres from $uri');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode != 200) {
        String message =
            'Failed to load practice centres (${response.statusCode}).';
        try {
          final errBody = jsonDecode(response.body);
          if (errBody is Map<String, dynamic> && errBody['detail'] != null) {
            message = errBody['detail'].toString();
          }
        } catch (_) {}
        AppLogger.w('PracticeCentreService: $message');
        throw UnexpectedFailure(message);
      }

      final data = jsonDecode(response.body) as List<dynamic>;
      final centres = data
          .map((e) => PracticeCentre.fromJson(e as Map<String, dynamic>))
          .toList();

      AppLogger.i(
          'PracticeCentreService: fetched ${centres.length} practice centres');
      return centres;
    } on Failure {
      rethrow;
    } catch (e, stack) {
      AppLogger.e('PracticeCentreService: error fetching practice centres', e, stack);
      throw UnexpectedFailure('Could not load practice centres: $e');
    }
  }

  /// Fetches raw patient queue tickets for a practice centre on a given date.
  Future<Map<String, int>> getQueueMetrics({
    required String baseUrl,
    required String accessToken,
    required String practiceCentreId,
    required String doctorId,
    String? visitDate,
  }) async {
    final dateStr = visitDate ?? DateTime.now().toIso8601String().split('T').first;
    final uri = Uri.parse(
        '$baseUrl/api/patient-queue?practiceCentreId=$practiceCentreId&doctorId=$doctorId&visitDate=$dateStr');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode != 200) {
        return {
          'total': 0,
          'waiting': 0,
          'active': 0,
          'completed': 0,
        };
      }

      final data = jsonDecode(response.body) as List<dynamic>;
      int total = data.length;
      int waiting = 0;
      int active = 0;
      int completed = 0;

      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final status = (item['status'] as num?)?.toInt() ?? 0;
          // Status enum values:
          // 0: Waiting, 1: Ready, 2: Called, 3: InConsultation, 4: Completed
          if (status == 0 || status == 1) {
            waiting++;
          } else if (status == 2 || status == 3) {
            active++;
          } else if (status == 4) {
            completed++;
          }
        }
      }

      return {
        'total': total,
        'waiting': waiting,
        'active': active,
        'completed': completed,
      };
    } catch (e) {
      AppLogger.w('PracticeCentreService: failed to fetch queue metrics: $e');
      return {
        'total': 0,
        'waiting': 0,
        'active': 0,
        'completed': 0,
      };
    }
  }
}
