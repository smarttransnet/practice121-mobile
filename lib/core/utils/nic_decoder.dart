class NicDecodeResult {
  const NicDecodeResult({
    required this.isValid,
    this.dateOfBirth,
    this.gender,
    this.age,
    this.normalizedNic,
    this.error,
  });

  final bool isValid;
  final String? dateOfBirth; // YYYY-MM-DD
  final String? gender; // 'Male' | 'Female'
  final int? age;
  final String? normalizedNic;
  final String? error;
}

final _nicRegex = RegExp(r'^(?:\d{9}[vVxX]|\d{12})$');

/// Normalizes NIC string: trims whitespace and converts trailing 'v'/'x' to uppercase ('V'/'X').
String? normalizeNic(String? input) {
  if (input == null) return null;
  final trimmed = input.trim();
  if (trimmed.length == 10) {
    final lastChar = trimmed[9].toUpperCase();
    return '${trimmed.substring(0, 9)}$lastChar';
  }
  return trimmed;
}

/// Checks whether the input string is a valid Sri Lankan NIC number.
bool isValidNic(String? input) {
  return decodeNic(input).isValid;
}

/// Decodes a Sri Lankan NIC number into DOB (YYYY-MM-DD), Gender, Age, and Normalized NIC.
NicDecodeResult decodeNic(String? input) {
  if (input == null || input.trim().isEmpty) {
    return const NicDecodeResult(
      isValid: false,
      error: 'NIC number is required.',
    );
  }

  final normalized = normalizeNic(input);
  if (normalized == null || !_nicRegex.hasMatch(normalized)) {
    return NicDecodeResult(
      isValid: false,
      normalizedNic: normalized,
      error: 'Please enter a valid Sri Lankan NIC number.',
    );
  }

  int year;
  int dayOfYearRaw;

  if (normalized.length == 10) {
    // Old format: 9 digits + V/X (e.g., 882441524V)
    year = 1900 + int.parse(normalized.substring(0, 2));
    dayOfYearRaw = int.parse(normalized.substring(2, 5));
  } else {
    // New format: 12 digits (e.g., 199824401524)
    year = int.parse(normalized.substring(0, 4));
    dayOfYearRaw = int.parse(normalized.substring(4, 7));
  }

  String gender;
  int actualDay;

  if (dayOfYearRaw > 500) {
    gender = 'Female';
    actualDay = dayOfYearRaw - 500;
  } else {
    gender = 'Male';
    actualDay = dayOfYearRaw;
  }

  final isLeapYear = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
  final maxDays = isLeapYear ? 366 : 365;

  if (actualDay < 1 || actualDay > maxDays) {
    return NicDecodeResult(
      isValid: false,
      normalizedNic: normalized,
      error: 'Invalid day component in NIC number.',
    );
  }

  // Calculate Date of Birth: Jan 1st of year + (actualDay - 1) days
  final dobDate = DateTime.utc(year, 1, 1).add(Duration(days: actualDay - 1));
  final yyyy = dobDate.year.toString().padLeft(4, '0');
  final mm = dobDate.month.toString().padLeft(2, '0');
  final dd = dobDate.day.toString().padLeft(2, '0');
  final dateOfBirth = '$yyyy-$mm-$dd';

  // Age calculation
  final today = DateTime.now();
  int age = today.year - year;
  final birthThisYear = DateTime(today.year, dobDate.month, dobDate.day);
  if (today.isBefore(birthThisYear)) {
    age--;
  }

  return NicDecodeResult(
    isValid: true,
    dateOfBirth: dateOfBirth,
    gender: gender,
    age: age,
    normalizedNic: normalized,
  );
}
