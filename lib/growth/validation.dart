import 'who_standards.dart';

/// Form validation for field data. Each function returns an error message, or null when valid.
/// Ranges are deliberately wide (they catch typos such as 75 kg instead of 7.5 kg); WHO's
/// implausible-z-score flags then catch values that are possible but very unlikely.
class Validate {
  static String? name(String? value, {String label = 'Name'}) {
    final v = value?.trim() ?? '';
    if (v.length < 2) return '$label must be at least 2 characters.';
    if (v.length > 80) return '$label must be at most 80 characters.';
    if (!RegExp(r"^[\p{L}\p{M} .'-]+$", unicode: true).hasMatch(v)) return '$label can only contain letters, spaces, . \' and -.';
    return null;
  }

  /// Sri Lankan numbers: 10 digits starting with 0, e.g. 0771234567. Optional.
  static String? phone(String? value) {
    final v = value?.replaceAll(RegExp(r'[\s-]'), '') ?? '';
    if (v.isEmpty) return null;
    return RegExp(r'^0\d{9}$').hasMatch(v) ? null : 'Enter a 10-digit phone number starting with 0.';
  }

  static String? dateOfBirth(DateTime? dob, {required DateTime today}) {
    if (dob == null) return 'Enter the date of birth.';
    if (dob.isAfter(today)) return 'Date of birth cannot be in the future.';
    if (WhoStandards.ageInDays(dob, today) > WhoStandards.maxAgeDays) {
      return 'This app follows children under 5 years (WHO standards cover 0–60 months).';
    }
    return null;
  }

  static String? measuredOn(DateTime? date, {required DateTime dob, required DateTime today}) {
    if (date == null) return 'Enter the measurement date.';
    if (date.isAfter(today)) return 'The measurement date cannot be in the future.';
    final age = WhoStandards.ageInDays(dob, date);
    if (age < 0) return 'The measurement date is before the date of birth.';
    if (age > WhoStandards.maxAgeDays) return 'The child was over 5 years old on this date.';
    return null;
  }

  static double? parseDecimal(String? value) => double.tryParse((value ?? '').trim().replaceAll(',', '.'));

  static String? weightKg(String? value, {bool required = false}) =>
      _range(value, label: 'Weight', unit: 'kg', min: 0.5, max: 40, required: required);

  static String? heightCm(String? value, {bool required = false}) =>
      _range(value, label: 'Length/height', unit: 'cm', min: 38, max: 130, required: required);

  static String? muacCm(String? value) => _range(value, label: 'MUAC', unit: 'cm', min: 5, max: 30, required: false);

  static String? _range(String? value, {required String label, required String unit, required double min, required double max, required bool required}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return required ? 'Enter the ${label.toLowerCase()}.' : null;
    final number = parseDecimal(text);
    if (number == null) return '$label must be a number.';
    if (number < min || number > max) return '$label must be between $min and $max $unit.';
    if (!RegExp(r'^\d+([.,]\d{1,2})?$').hasMatch(text)) return 'Use at most 2 decimal places.';
    return null;
  }
}
