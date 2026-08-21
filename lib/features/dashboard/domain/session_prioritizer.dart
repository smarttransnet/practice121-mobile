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
      final todaySlots = <DaySessionSlot>[];
      final dateStr = now.toIso8601String().split('T').first;

      // Search all session groups for today's schedule
      for (final group in centre.sessionGroups) {
        if (group.daysOff.contains(dateStr)) continue;

        final isSpecificDateMatch = group.specificDate == dateStr ||
            group.specificDates.contains(dateStr);
        final isDayOfWeekMatch = group.daysOfWeek.contains(currentDayAbbr);

        if (isSpecificDateMatch || isDayOfWeekMatch) {
          if (group.timeBlocks.isNotEmpty) {
            for (final tb in group.timeBlocks) {
              final startMin = _parseTimeToMinutes(tb.startTime);
              final endMin = _parseTimeToMinutes(tb.endTime);
              SessionScheduleStatus slotStatus;

              if (currentTimeInMinutes >= startMin &&
                  currentTimeInMinutes <= endMin) {
                slotStatus = SessionScheduleStatus.active;
              } else if (currentTimeInMinutes < startMin) {
                slotStatus = SessionScheduleStatus.upcoming;
              } else {
                slotStatus = SessionScheduleStatus.completed;
              }

              todaySlots.add(
                DaySessionSlot(
                  id: tb.id.isNotEmpty ? tb.id : group.id,
                  groupId: group.id,
                  label: tb.label.isNotEmpty ? tb.label : 'Session',
                  startTime: tb.startTime,
                  endTime: tb.endTime,
                  timeRange: '${tb.startTime} - ${tb.endTime}',
                  status: slotStatus,
                ),
              );
            }
          } else {
            todaySlots.add(
              DaySessionSlot(
                id: group.id,
                groupId: group.id,
                label: 'Scheduled Session',
                startTime: '09:00',
                endTime: '17:00',
                timeRange: group.daysOfWeek.join(', '),
                status: SessionScheduleStatus.active,
              ),
            );
          }
        }
      }

      SessionScheduleStatus overallStatus =
          SessionScheduleStatus.notScheduledToday;
      String timeRangeLabel = 'No Session Scheduled Today';
      int priorityRank = 1000;
      DaySessionSlot? bestSlot;

      if (todaySlots.isNotEmpty) {
        // Sort slots by start time
        todaySlots.sort((a, b) =>
            _parseTimeToMinutes(a.startTime).compareTo(_parseTimeToMinutes(b.startTime)));

        // Find active slot first, or next upcoming slot, or last completed slot
        DaySessionSlot? activeSlot;
        DaySessionSlot? upcomingSlot;

        for (final slot in todaySlots) {
          if (slot.status == SessionScheduleStatus.active && activeSlot == null) {
            activeSlot = slot;
          } else if (slot.status == SessionScheduleStatus.upcoming && upcomingSlot == null) {
            upcomingSlot = slot;
          }
        }

        if (activeSlot != null) {
          overallStatus = SessionScheduleStatus.active;
          bestSlot = activeSlot;
          priorityRank = 10;
          timeRangeLabel = '${activeSlot.label} (${activeSlot.timeRange})';
        } else if (upcomingSlot != null) {
          overallStatus = SessionScheduleStatus.upcoming;
          bestSlot = upcomingSlot;
          final startMin = _parseTimeToMinutes(upcomingSlot.startTime);
          final minutesUntilStart = startMin - currentTimeInMinutes;
          priorityRank = 100 + minutesUntilStart;
          timeRangeLabel = '${upcomingSlot.label} (${upcomingSlot.timeRange})';
        } else {
          overallStatus = SessionScheduleStatus.completed;
          bestSlot = todaySlots.last;
          final endMin = _parseTimeToMinutes(bestSlot.endTime);
          priorityRank = 500 + (currentTimeInMinutes - endMin);
          timeRangeLabel = '${bestSlot.label} (${bestSlot.timeRange})';
        }
      } else if (centre.sessionGroups.isNotEmpty) {
        // Find next upcoming day label
        final firstGroup = centre.sessionGroups.first;
        if (firstGroup.specificDates.isNotEmpty) {
          timeRangeLabel = 'Scheduled on ${firstGroup.specificDates.join(', ')}';
        } else if (firstGroup.specificDate != null) {
          timeRangeLabel = 'Scheduled on ${firstGroup.specificDate}';
        } else if (firstGroup.daysOfWeek.isNotEmpty) {
          timeRangeLabel = 'Scheduled on ${firstGroup.daysOfWeek.join(', ')}';
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
          status: overallStatus,
          timeRangeLabel: timeRangeLabel,
          totalBookedCount: metrics['total'] ?? 0,
          waitingCount: metrics['waiting'] ?? 0,
          activeCount: metrics['active'] ?? 0,
          completedCount: metrics['completed'] ?? 0,
          priorityRank: priorityRank,
          todaySlots: todaySlots,
          selectedSlot: bestSlot,
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
