import 'package:flutter_test/flutter_test.dart';
import 'package:note365_mobile/features/dashboard/data/models/practice_centre.dart';

void main() {
  group('Start Session Validation Logic', () {
    test('Session scheduled today detection', () {
      const activeSummary = CentreSessionSummary(
        centre: PracticeCentre(
          id: 'c1',
          doctorId: 'd1',
          clinicName: 'Health Clinic',
          districtName: 'Colombo',
          mohAreaName: 'Area 1',
          placeName: 'Central',
          sessionGroups: [],
        ),
        status: SessionScheduleStatus.active,
        timeRangeLabel: '09:00 - 17:00',
        totalBookedCount: 5,
        waitingCount: 3,
        activeCount: 1,
        completedCount: 1,
      );

      const notTodaySummary = CentreSessionSummary(
        centre: PracticeCentre(
          id: 'c2',
          doctorId: 'd1',
          clinicName: 'Suburban Clinic',
          districtName: 'Kandy',
          mohAreaName: 'Area 2',
          placeName: 'North',
          sessionGroups: [],
        ),
        status: SessionScheduleStatus.notScheduledToday,
        timeRangeLabel: 'Scheduled on MON, WED',
        totalBookedCount: 0,
        waitingCount: 0,
        activeCount: 0,
        completedCount: 0,
      );

      final isActiveToday =
          activeSummary.status != SessionScheduleStatus.notScheduledToday;
      final isNotTodayScheduled =
          notTodaySummary.status != SessionScheduleStatus.notScheduledToday;

      expect(isActiveToday, isTrue);
      expect(isNotTodayScheduled, isFalse);
    });

    test('Queue patient presence evaluation', () {
      const summaryWithPatients = CentreSessionSummary(
        centre: PracticeCentre(
          id: 'c1',
          doctorId: 'd1',
          clinicName: 'Health Clinic',
          districtName: 'Colombo',
          mohAreaName: 'Area 1',
          placeName: 'Central',
          sessionGroups: [],
        ),
        status: SessionScheduleStatus.active,
        timeRangeLabel: '09:00 - 17:00',
        totalBookedCount: 3,
        waitingCount: 2,
        activeCount: 1,
        completedCount: 0,
      );

      const completedSessionSummary = CentreSessionSummary(
        centre: PracticeCentre(
          id: 'c2',
          doctorId: 'd1',
          clinicName: 'Suburban Clinic',
          districtName: 'Kandy',
          mohAreaName: 'Area 2',
          placeName: 'North',
          sessionGroups: [],
        ),
        status: SessionScheduleStatus.completed,
        timeRangeLabel: '09:00 - 17:00',
        totalBookedCount: 5,
        waitingCount: 0,
        activeCount: 0,
        completedCount: 5,
      );

      final hasPatients = summaryWithPatients.waitingCount + summaryWithPatients.activeCount > 0;
      final activeQueueCount = completedSessionSummary.waitingCount + completedSessionSummary.activeCount;

      expect(hasPatients, isTrue);
      expect(activeQueueCount, equals(0));
    });
  });
}
