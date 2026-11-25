import 'package:flutter_test/flutter_test.dart';
import 'package:growth_monitor/growth/validation.dart';

void main() {
  final today = DateTime(2026, 11, 25);

  test('names allow Sinhala, Tamil and Latin letters but not digits', () {
    expect(Validate.name('Nethmi Perera'), isNull);
    expect(Validate.name("D'Silva-Fernando"), isNull);
    expect(Validate.name('නෙත්මි'), isNull);
    expect(Validate.name('நிலா'), isNull);
    expect(Validate.name('A'), 'Name must be at least 2 characters.');
    expect(Validate.name('Baby 2'), contains('can only contain letters'));
  });

  test('phone numbers are optional but must be 10 digits starting with 0', () {
    expect(Validate.phone(''), isNull);
    expect(Validate.phone('077 123-4567'), isNull);
    expect(Validate.phone('771234567'), isNotNull);
  });

  test('date of birth must be in the past and under 5 years', () {
    expect(Validate.dateOfBirth(null, today: today), 'Enter the date of birth.');
    expect(Validate.dateOfBirth(DateTime(2026, 12, 1), today: today), contains('future'));
    expect(Validate.dateOfBirth(DateTime(2021, 1, 1), today: today), contains('under 5 years'));
    expect(Validate.dateOfBirth(DateTime(2024, 1, 1), today: today), isNull);
  });

  test('visit dates must fall between birth and today, within 0–60 months', () {
    final dob = DateTime(2025, 6, 10);
    expect(Validate.measuredOn(DateTime(2025, 6, 9), dob: dob, today: today), contains('before the date of birth'));
    expect(Validate.measuredOn(DateTime(2026, 12, 1), dob: dob, today: today), contains('future'));
    expect(Validate.measuredOn(today, dob: dob, today: today), isNull);
  });

  test('measurement ranges catch typos', () {
    expect(Validate.weightKg('7.5'), isNull);
    expect(Validate.weightKg('7,5'), isNull, reason: 'comma decimal separator');
    expect(Validate.weightKg('75'), 'Weight must be between 0.5 and 40.0 kg.');
    expect(Validate.weightKg('7.555'), 'Use at most 2 decimal places.');
    expect(Validate.weightKg('', required: true), 'Enter the weight.');
    expect(Validate.heightCm('abc'), 'Length/height must be a number.');
    expect(Validate.heightCm('200'), contains('between 38.0 and 130.0'));
    expect(Validate.muacCm('11.4'), isNull);
  });
}
