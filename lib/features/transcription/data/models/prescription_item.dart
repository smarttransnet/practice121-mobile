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
        // Fallback: parse plain text lines
        final lines = str.split('\n');
        final items = <PrescriptionItem>[];
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty && !trimmed.toLowerCase().startsWith('doctor prescription')) {
            final cleaned = trimmed.replaceAll(RegExp(r'^\d+[\.\)\-]\s*'), '').replaceAll(RegExp(r'^[\-\*•]\s*'), '');
            if (cleaned.isNotEmpty) {
              items.add(PrescriptionItem(genericName: cleaned));
            }
          }
        }
        return items;
      }
    }
    return [];
  }
}
