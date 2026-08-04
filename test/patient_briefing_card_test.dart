import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note365_mobile/features/transcription/data/services/queue_service.dart';
import 'package:note365_mobile/features/transcription/presentation/widgets/patient_briefing_card.dart';

void main() {
  group('PatientBriefingCard Widget Tests', () {
    final samplePatient = QueuePatient(
      id: 'p-101',
      patientName: 'Komal de Silva',
      queueNumber: 1,
      patientMobile: '+94771234567',
    );

    testWidgets('renders patient details and queue token correctly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatientBriefingCard(
              patient: samplePatient,
              clinicName: 'Health First Clinic',
              onStartSession: () {},
            ),
          ),
        ),
      );

      expect(find.text('Komal de Silva'), findsOneWidget);
      expect(find.text('#1'), findsNWidgets(2)); // Badge and details column
      expect(find.text('+94771234567'), findsOneWidget);
      expect(find.textContaining('Health First Clinic'), findsOneWidget);
      expect(find.text('Start Session'), findsOneWidget);
    });

    testWidgets('invokes onStartSession callback when Start Session is tapped',
        (WidgetTester tester) async {
      bool sessionStarted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatientBriefingCard(
              patient: samplePatient,
              clinicName: 'Health First Clinic',
              onStartSession: () {
                sessionStarted = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start Session'));
      await tester.pump();

      expect(sessionStarted, isTrue);
    });
  });
}
