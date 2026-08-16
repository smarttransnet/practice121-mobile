import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/errors/failures.dart';
import '../../../../core/logging/app_logger.dart';

class ClinicalNoteSummary {
  const ClinicalNoteSummary({
    required this.id,
    required this.patientId,
    this.doctorId,
    this.practiceCentreId,
    this.ticketId,
    this.visitDate,
    this.createdAt,
    this.clinicName,
    this.preview,
  });

  final String id;
  final String patientId;
  final String? doctorId;
  final String? practiceCentreId;
  final String? ticketId;
  final String? visitDate;
  final String? createdAt;
  final String? clinicName;
  final String? preview;

  factory ClinicalNoteSummary.fromJson(Map<String, dynamic> json) {
    return ClinicalNoteSummary(
      id: json['id']?.toString() ?? '',
      patientId: json['patientId']?.toString() ?? '',
      doctorId: json['doctorId']?.toString(),
      practiceCentreId: json['practiceCentreId']?.toString(),
      ticketId: json['ticketId']?.toString(),
      visitDate: json['visitDate']?.toString(),
      createdAt: json['createdAt']?.toString(),
      clinicName: json['clinicName']?.toString(),
      preview: json['preview']?.toString(),
    );
  }
}

class ClinicalNoteDetail {
  const ClinicalNoteDetail({
    required this.id,
    required this.patientId,
    required this.noteText,
    this.doctorId,
    this.practiceCentreId,
    this.ticketId,
    this.visitDate,
    this.createdAt,
    this.clinicName,
    this.patientName,
    this.patientMobile,
    this.fullTranscript,
    this.amendmentHistory = const [],
  });

  final String id;
  final String patientId;
  final String noteText;
  final String? doctorId;
  final String? practiceCentreId;
  final String? ticketId;
  final String? visitDate;
  final String? createdAt;
  final String? clinicName;
  final String? patientName;
  final String? patientMobile;
  final String? fullTranscript;
  final List<String> amendmentHistory;

  factory ClinicalNoteDetail.fromJson(Map<String, dynamic> json) {
    final amendments = <String>[];
    final raw = json['amendmentHistory'];
    if (raw is List) {
      for (final item in raw) {
        if (item != null) amendments.add(item.toString());
      }
    }
    return ClinicalNoteDetail(
      id: json['id']?.toString() ?? '',
      patientId: json['patientId']?.toString() ?? '',
      noteText: json['noteText']?.toString() ?? '',
      doctorId: json['doctorId']?.toString(),
      practiceCentreId: json['practiceCentreId']?.toString(),
      ticketId: json['ticketId']?.toString(),
      visitDate: json['visitDate']?.toString(),
      createdAt: json['createdAt']?.toString(),
      clinicName: json['clinicName']?.toString(),
      patientName: json['patientName']?.toString(),
      patientMobile: json['patientMobile']?.toString(),
      fullTranscript: json['fullTranscript']?.toString(),
      amendmentHistory: amendments,
    );
  }
}

class SaveClinicalNoteResult {
  const SaveClinicalNoteResult({
    required this.noteId,
    required this.fhirPatientId,
    required this.fhirDocumentReferenceId,
    this.fhirEncounterId,
  });

  final String noteId;
  final String fhirPatientId;
  final String fhirDocumentReferenceId;
  final String? fhirEncounterId;

  factory SaveClinicalNoteResult.fromJson(Map<String, dynamic> json) {
    return SaveClinicalNoteResult(
      noteId: json['noteId']?.toString() ?? '',
      fhirPatientId: json['fhirPatientId']?.toString() ?? '',
      fhirDocumentReferenceId:
          json['fhirDocumentReferenceId']?.toString() ?? '',
      fhirEncounterId: json['fhirEncounterId']?.toString(),
    );
  }
}

class ClinicalNoteFhirService {
  Future<SaveClinicalNoteResult> saveClinicalNote({
    required Uri url,
    required String patientId,
    required String doctorId,
    required String practiceCentreId,
    required String noteText,
    String? ticketId,
    String? visitDate,
    String? clinicName,
    String? patientName,
    String? patientMobile,
    String? fullTranscript,
    List<String> amendmentHistory = const [],
  }) async {
    if (patientId.trim().isEmpty) {
      throw const UnexpectedFailure('patientId is required to save the clinical note.');
    }
    if (doctorId.trim().isEmpty) {
      throw const UnexpectedFailure('doctorId is required to save the clinical note.');
    }
    if (practiceCentreId.trim().isEmpty) {
      throw const UnexpectedFailure(
          'practiceCentreId is required to save the clinical note.');
    }
    if (noteText.trim().isEmpty) {
      throw const UnexpectedFailure('noteText is required to save the clinical note.');
    }

    try {
      AppLogger.i(
        'Saving clinical note to FHIR — patientId=$patientId, ticketId=$ticketId',
      );
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'patientId': patientId,
          'doctorId': doctorId,
          'practiceCentreId': practiceCentreId,
          'noteText': noteText,
          if (ticketId != null && ticketId.isNotEmpty) 'ticketId': ticketId,
          if (visitDate != null && visitDate.isNotEmpty) 'visitDate': visitDate,
          if (clinicName != null && clinicName.isNotEmpty) 'clinicName': clinicName,
          if (patientName != null && patientName.isNotEmpty) 'patientName': patientName,
          if (patientMobile != null && patientMobile.isNotEmpty)
            'patientMobile': patientMobile,
          if (fullTranscript != null && fullTranscript.isNotEmpty)
            'fullTranscript': fullTranscript,
          if (amendmentHistory.isNotEmpty) 'amendmentHistory': amendmentHistory,
        }),
      );

      if (response.statusCode != 200) {
        throw UnexpectedFailure(_extractError(response, 'Save clinical note'));
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return SaveClinicalNoteResult.fromJson(data);
    } on Failure {
      rethrow;
    } catch (e, stack) {
      AppLogger.e('Save clinical note failed', e, stack);
      throw UnexpectedFailure('Could not save clinical note to FHIR: $e');
    }
  }

  Future<List<ClinicalNoteSummary>> listClinicalNotes({
    required Uri baseUrl,
    required String patientId,
    String? doctorId,
    String? practiceCentreId,
  }) async {
    if (patientId.trim().isEmpty) {
      throw const UnexpectedFailure('patientId is required to list clinical notes.');
    }

    final query = <String, String>{
      'patientId': patientId,
      if (doctorId != null && doctorId.isNotEmpty) 'doctorId': doctorId,
      if (practiceCentreId != null && practiceCentreId.isNotEmpty)
        'practiceCentreId': practiceCentreId,
    };
    final uri = baseUrl.replace(queryParameters: query);

    try {
      AppLogger.i('Listing clinical notes for patientId=$patientId');
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw UnexpectedFailure(_extractError(response, 'List clinical notes'));
      }

      final data = jsonDecode(response.body);
      if (data is! List) return const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(ClinicalNoteSummary.fromJson)
          .toList();
    } on Failure {
      rethrow;
    } catch (e, stack) {
      AppLogger.e('List clinical notes failed', e, stack);
      throw UnexpectedFailure('Could not load prior clinical notes: $e');
    }
  }

  Future<ClinicalNoteDetail> getClinicalNote({
    required Uri url,
  }) async {
    try {
      final response = await http.get(url);
      if (response.statusCode == 404) {
        throw const UnexpectedFailure('Clinical note not found.');
      }
      if (response.statusCode != 200) {
        throw UnexpectedFailure(_extractError(response, 'Get clinical note'));
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ClinicalNoteDetail.fromJson(data);
    } on Failure {
      rethrow;
    } catch (e, stack) {
      AppLogger.e('Get clinical note failed', e, stack);
      throw UnexpectedFailure('Could not load clinical note: $e');
    }
  }

  String _extractError(http.Response response, String action) {
    var message = '$action failed (${response.statusCode}).';
    try {
      final errBody = jsonDecode(response.body);
      if (errBody is Map<String, dynamic>) {
        if (errBody['error'] != null) {
          message = errBody['error'].toString();
        } else if (errBody['detail'] != null) {
          message = errBody['detail'].toString();
        } else if (errBody['title'] != null) {
          message = errBody['title'].toString();
        }
      }
    } catch (_) {}
    return message;
  }
}
