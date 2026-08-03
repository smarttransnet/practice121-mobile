/// Data models for Doctor Practice Centres and Session schedules returned by
/// `GET api/practice-centres` and queue statistics.

enum SessionScheduleStatus {
  active,
  upcoming,
  completed,
  notScheduledToday,
}

class TimeBlock {
  const TimeBlock({
    required this.id,
    required this.label,
    required this.startTime,
    required this.endTime,
  });

  final String id;
  final String label;
  final String startTime;
  final String endTime;

  factory TimeBlock.fromJson(Map<String, dynamic> json) {
    return TimeBlock(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? 'Session',
      startTime: json['startTime']?.toString() ?? '09:00',
      endTime: json['endTime']?.toString() ?? '17:00',
    );
  }
}

class SessionGroup {
  const SessionGroup({
    required this.id,
    required this.daysOfWeek,
    required this.timeBlocks,
  });

  final String id;
  final List<String> daysOfWeek;
  final List<TimeBlock> timeBlocks;

  factory SessionGroup.fromJson(Map<String, dynamic> json) {
    return SessionGroup(
      id: json['id']?.toString() ?? '',
      daysOfWeek: (json['daysOfWeek'] as List<dynamic>?)
              ?.map((e) => e.toString().toUpperCase())
              .toList() ??
          [],
      timeBlocks: (json['timeBlocks'] as List<dynamic>?)
              ?.map((e) => TimeBlock.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class PracticeCentre {
  const PracticeCentre({
    required this.id,
    required this.doctorId,
    required this.clinicName,
    required this.districtName,
    required this.mohAreaName,
    required this.placeName,
    this.maxPatients,
    required this.sessionGroups,
  });

  final String id;
  final String doctorId;
  final String clinicName;
  final String districtName;
  final String mohAreaName;
  final String placeName;
  final int? maxPatients;
  final List<SessionGroup> sessionGroups;

  factory PracticeCentre.fromJson(Map<String, dynamic> json) {
    return PracticeCentre(
      id: json['id']?.toString() ?? '',
      doctorId: json['doctorId']?.toString() ?? '',
      clinicName: json['clinicName']?.toString() ?? 'Practice Centre',
      districtName: json['districtName']?.toString() ?? '',
      mohAreaName: json['mohAreaName']?.toString() ?? '',
      placeName: json['placeName']?.toString() ?? '',
      maxPatients: (json['maxPatients'] as num?)?.toInt(),
      sessionGroups: (json['sessionGroups'] as List<dynamic>?)
              ?.map((e) => SessionGroup.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Evaluated summary of a practice centre session for the Dashboard view.
class CentreSessionSummary {
  const CentreSessionSummary({
    required this.centre,
    required this.status,
    required this.timeRangeLabel,
    required this.totalBookedCount,
    required this.waitingCount,
    required this.activeCount,
    required this.completedCount,
    this.priorityRank = 999,
  });

  final PracticeCentre centre;
  final SessionScheduleStatus status;
  final String timeRangeLabel;
  final int totalBookedCount;
  final int waitingCount;
  final int activeCount;
  final int completedCount;
  final int priorityRank;
}
