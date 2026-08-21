class AgeInfo {
  const AgeInfo({
    required this.years,
    required this.months,
    required this.formatted,
  });

  final int years;
  final int months;
  final String formatted;
}

/// Calculates age in years and months from a DateTime or YYYY-MM-DD string.
AgeInfo calculateAge(dynamic dobInput) {
  if (dobInput == null) {
    return const AgeInfo(years: 0, months: 0, formatted: '');
  }

  DateTime? dob;
  if (dobInput is DateTime) {
    dob = dobInput;
  } else if (dobInput is String) {
    if (dobInput.trim().isEmpty) {
      return const AgeInfo(years: 0, months: 0, formatted: '');
    }
    dob = DateTime.tryParse(dobInput.trim());
  }

  if (dob == null) {
    return const AgeInfo(years: 0, months: 0, formatted: '');
  }

  final today = DateTime.now();
  int years = today.year - dob.year;
  int months = today.month - dob.month;
  final dayDiff = today.day - dob.day;

  if (dayDiff < 0) {
    months--;
  }

  if (months < 0) {
    years--;
    months += 12;
  }

  if (years < 0) {
    return const AgeInfo(years: 0, months: 0, formatted: '0 mos');
  }

  final parts = <String>[];
  if (years > 0) {
    parts.add('$years yr${years > 1 ? 's' : ''}');
  }
  if (months > 0 || years == 0) {
    parts.add('$months mo${months != 1 ? 's' : ''}');
  }

  return AgeInfo(
    years: years,
    months: months,
    formatted: parts.join(' '),
  );
}
