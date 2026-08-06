import 'dart:convert';

/// Represents a single prescription item entry.
class PrescriptionItem {
  PrescriptionItem({
    this.genericName,
    this.brandName,
    this.dose,
    this.frequency,
    this.duration,
  });

  String? genericName;
  String? brandName;
  String? dose;
  String? frequency;
  String? duration;

  /// Returns the formatted medicine column string.
  /// If both generic and brand name are present: "GenericName / BrandName"
  /// If only generic: "GenericName"
  /// If only brand: "BrandName"
  /// If both are null/empty: ""
  String get medicineDisplay {
    final g = genericName?.trim() ?? '';
    final b = brandName?.trim() ?? '';
    if (g.isNotEmpty && b.isNotEmpty) {
      return '$g / $b';
    } else if (g.isNotEmpty) {
      return g;
    } else if (b.isNotEmpty) {
      return b;
    }
    return '';
  }

  /// Cleans null, N/A, undefined, * strings to empty string.
  static String? cleanValue(String? val) {
    if (val == null) return null;
    final trimmed = val.trim();
    final lower = trimmed.toLowerCase();
    if (trimmed.isEmpty ||
        lower == 'null' ||
        lower == 'n/a' ||
        lower == 'undefined' ||
        trimmed == '*') {
      return null;
    }
    return trimmed;
  }

  /// Returns a clean sentence representation for reading mode.
  String toSentenceString() {
    final med = medicineDisplay;
    final d = cleanValue(dose);
    final f = cleanValue(frequency);
    final dur = cleanValue(duration);

    final parts = <String>[];
    if (med.isNotEmpty) parts.add(med);
    if (d != null) parts.add(d);
    if (f != null) parts.add(f);
    if (dur != null) parts.add(dur);

    return parts.join(' - ');
  }

  /// Converts text to plain ASCII only, eliminating Unicode characters for SMS compatibility.
  static String sanitizeToAscii(String input) {
    return input
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('–', '-')
        .replaceAll('×', 'x')
        .replaceAll('•', '-')
        .replaceAll('…', '...')
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('”', '"')
        .replaceAll('“', '"')
        .replaceAll(RegExp(r'[^\x00-\x7F]'), '');
  }

  /// Returns plain ASCII sentence format suitable for SMS delivery.
  String toSmsAsciiString() {
    return sanitizeToAscii(toSentenceString());
  }

  factory PrescriptionItem.fromJson(Map<String, dynamic> json) {
    return PrescriptionItem(
      genericName: cleanValue(json['GenericName']?.toString() ?? json['genericName']?.toString()),
      brandName: cleanValue(json['BrandName']?.toString() ?? json['brandName']?.toString()),
      dose: cleanValue(json['Dose']?.toString() ?? json['dose']?.toString()),
      frequency: cleanValue(json['Frequency']?.toString() ?? json['frequency']?.toString()),
      duration: cleanValue(json['Duration']?.toString() ?? json['duration']?.toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'GenericName': cleanValue(genericName),
      'BrandName': cleanValue(brandName),
      'Dose': cleanValue(dose),
      'Frequency': cleanValue(frequency),
      'Duration': cleanValue(duration),
    };
  }

  /// Parses JSON array, JSON object, or plain text into a list of [PrescriptionItem].
  static List<PrescriptionItem> fromRaw(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((item) {
        if (item is Map<String, dynamic>) {
          return PrescriptionItem.fromJson(item);
        }
        return PrescriptionItem(genericName: item.toString());
      }).toList();
    }
    if (raw is String) {
      final str = raw.trim();
      if (str.isEmpty) return [];
      try {
        final decoded = jsonDecode(str);
        if (decoded is List) {
          return decoded.map((e) => PrescriptionItem.fromJson(e as Map<String, dynamic>)).toList();
        } else if (decoded is Map<String, dynamic>) {
          return [PrescriptionItem.fromJson(decoded)];
        }
      } catch (_) {
        // Fallback: parse plain text lines into separate structured fields
        final lines = str.split('\n');
        final items = <PrescriptionItem>[];
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty && !trimmed.toLowerCase().startsWith('doctor prescription')) {
            final cleaned = trimmed.replaceAll(RegExp(r'^\d+[\.\)\-]\s*'), '').replaceAll(RegExp(r'^[\-\*•]\s*'), '');
            if (cleaned.isNotEmpty) {
              items.add(parseLineToItem(cleaned));
            }
          }
        }
        return items;
      }
    }
    return [];
  }

  /// Parses a single text line into a structured [PrescriptionItem] with separate fields.
  static PrescriptionItem parseLineToItem(String line) {
    var text = line.trim();
    if (text.isEmpty) return PrescriptionItem();

    // Check if line uses hyphen delimiters ("Generic / Brand - Dose - Freq - Duration")
    if (text.contains(' - ')) {
      final parts = text.split(' - ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      String? gen;
      String? brand;
      String? dose;
      String? freq;
      String? dur;

      if (parts.isNotEmpty) {
        final medPart = parts[0];
        if (medPart.contains('/')) {
          final medSub = medPart.split('/');
          gen = medSub[0].trim();
          brand = medSub.sublist(1).join('/').trim();
        } else {
          gen = medPart;
        }
      }
      if (parts.length > 1) dose = parts[1];
      if (parts.length > 2) freq = parts[2];
      if (parts.length > 3) dur = parts[3];

      return PrescriptionItem(
        genericName: cleanValue(gen),
        brandName: cleanValue(brand),
        dose: cleanValue(dose),
        frequency: cleanValue(freq),
        duration: cleanValue(dur),
      );
    }

    // Token/regex match for duration, frequency, dose if hyphens are absent
    String? dur;
    final durMatch = RegExp(r'\b\d+\s*(?:days?|weeks?|months?|d|w|m)\b', caseSensitive: false).firstMatch(text);
    if (durMatch != null) {
      dur = durMatch.group(0);
      text = text.replaceFirst(durMatch.group(0)!, '').trim();
    }

    String? freq;
    final freqMatch = RegExp(r'\b(?:OD|BD|TDS|QDS|STAT|PRN|Daily|Nightly|TID|BID|QID|Q4H|Q6H|Q8H|Q12H|1-0-1|1-1-1|1-0-0|0-0-1)\b', caseSensitive: false).firstMatch(text);
    if (freqMatch != null) {
      freq = freqMatch.group(0);
      text = text.replaceFirst(freqMatch.group(0)!, '').trim();
    }

    String? dose;
    final doseMatch = RegExp(r'\b\d+(?:\.\d+)?\s*(?:mg|g|ml|mcg|tablets?|capsules?|pills?|puffs?|drops?|u|units?)\b', caseSensitive: false).firstMatch(text);
    if (doseMatch != null) {
      dose = doseMatch.group(0);
      text = text.replaceFirst(doseMatch.group(0)!, '').trim();
    }

    String? gen;
    String? brand;
    final cleanMed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleanMed.contains('/')) {
      final parts = cleanMed.split('/');
      gen = parts[0].trim();
      brand = parts.sublist(1).join('/').trim();
    } else {
      gen = cleanMed;
    }

    return PrescriptionItem(
      genericName: cleanValue(gen),
      brandName: cleanValue(brand),
      dose: cleanValue(dose),
      frequency: cleanValue(freq),
      duration: cleanValue(dur),
    );
  }
}
