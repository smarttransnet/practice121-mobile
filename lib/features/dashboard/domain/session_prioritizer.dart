import '../data/models/practice_centre.dart';

/// Intelligent prioritization engine for doctor practice centre sessions.
///
/// Evaluates each practice centre against the current date and time to order
/// sessions so the doctor immediately identifies the next session to attend.
class SessionPrioritizer {
  /// Abbreviated day names matching backend format (MON, TUE, WED, THU, FRI, SAT, SUN).
  static const List<String> dayNames = [
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
    'SUN'
  ];

  /// Evaluates and prioritizes a list of [PracticeCentre] items for the current [now] time.
  static List<CentreSessionSummary> prioritizeCentres({
    required List<PracticeCentre> centres,
    required Map<String, Map<String, int>> queueMetricsMap,
    DateTime? nowOverride,
  }) {
    final now = nowOverride ?? DateTime.now();
    final currentDayAbbr = dayNames[now.weekday - 1];
    final currentTimeInMinutes = now.hour * 60 + now.minute;

    final summaries = <CentreSessionSummary>[];

    for (final centre in centres) {
      TimeBlock? todayTimeBlock;
      bool isScheduledToday = false;

      final dateStr = now.toIso8601String().split('T').first;

      // Search session groups for today's schedule
      for (final group in centre.sessionGroups) {
        if (group.daysOff.contains(dateStr)) continue;

        final isSpecificDateMatch = group.specificDate == dateStr;
        final isDayOfWeekMatch = group.daysOfWeek.contains(currentDayAbbr);
        
        if (isSpecificDateMatch || (group.specificDate == null && isDayOfWeekMatch)) {
          isScheduledToday = true;
          if (group.timeBlocks.isNotEmpty) {
            todayTimeBlock = group.timeBlocks.first;
          }
          break;
        }
      }

      SessionScheduleStatus status = SessionScheduleStatus.notScheduledToday;
      String timeRangeLabel = 'No Session Scheduled Today';
      int priorityRank = 1000;

      if (isScheduledToday) {
        final startTimeStr = todayTimeBlock?.startTime ?? '09:00';
        final endTimeStr = todayTimeBlock?.endTime ?? '17:00';
        final label = todayTimeBlock?.label ?? 'Session';

        timeRangeLabel = '$label ($startTimeStr - $endTimeStr)';

        final startMinutes = _parseTimeToMinutes(startTimeStr);
        final endMinutes = _parseTimeToMinutes(endTimeStr);

        if (currentTimeInMinutes >= startMinutes &&
            currentTimeInMinutes <= endMinutes) {
          // Currently ACTIVE session — top priority
          status = SessionScheduleStatus.active;
          priorityRank = 10;
        } else if (currentTimeInMinutes < startMinutes) {
          // UPCOMING session today — sorted by how soon it starts
          status = SessionScheduleStatus.upcoming;
          final minutesUntilStart = startMinutes - currentTimeInMinutes;
          priorityRank = 100 + minutesUntilStart;
        } else {
          // COMPLETED session today
          status = SessionScheduleStatus.completed;
          priorityRank = 500 + (currentTimeInMinutes - endMinutes);
        }
      } else if (centre.sessionGroups.isNotEmpty) {
        // Find next upcoming day label
        final firstGroup = centre.sessionGroups.first;
        if (firstGroup.specificDate != null) {
          timeRangeLabel = 'Scheduled on ${firstGroup.specificDate}';
        } else if (firstGroup.daysOfWeek.isNotEmpty) {
          timeRangeLabel =
              'Scheduled on ${firstGroup.daysOfWeek.join(', ')}';
        }
      }

      final metrics = queueMetricsMap[centre.id] ??
          {
            'total': 0,
            'waiting': 0,
            'active': 0,
            'completed': 0,
          };

      summaries.add(
        CentreSessionSummary(
          centre: centre,
          status: status,
          timeRangeLabel: timeRangeLabel,
          totalBookedCount: metrics['total'] ?? 0,
          waitingCount: metrics['waiting'] ?? 0,
          activeCount: metrics['active'] ?? 0,
          completedCount: metrics['completed'] ?? 0,
          priorityRank: priorityRank,
        ),
      );
    }

    // Sort by priorityRank (lowest numerical rank first = highest priority)
    summaries.sort((a, b) => a.priorityRank.compareTo(b.priorityRank));
    return summaries;
  }

  static int _parseTimeToMinutes(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        return hours * 60 + minutes;
      }
    } catch (_) {}
    return 9 * 60; // Default 09:00
  }
}
