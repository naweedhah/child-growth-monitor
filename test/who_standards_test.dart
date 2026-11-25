import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:growth_monitor/growth/assessment.dart';
import 'package:growth_monitor/growth/lms.dart';
import 'package:growth_monitor/growth/who_standards.dart';

WhoStandards loadStandards() => WhoStandards.fromTsv(
      wei: File('assets/who/weianthro.txt').readAsStringSync(),
      len: File('assets/who/lenanthro.txt').readAsStringSync(),
      wfl: File('assets/who/wflanthro.txt').readAsStringSync(),
      wfh: File('assets/who/wfhanthro.txt').readAsStringSync(),
    );

void main() {
  final who = loadStandards();

  group('LMS maths', () {
    const lms = Lms(0.3487, 3.3464, 0.14602); // boys, weight-for-age, birth

    test('the median has z = 0 and valueAt inverts rawZ', () {
      expect(lms.rawZ(3.3464), closeTo(0, 1e-9));
      for (final z in [-3.0, -2.0, -1.0, 1.0, 2.0, 3.0]) {
        expect(lms.rawZ(lms.valueAt(z)), closeTo(z, 1e-9));
      }
    });

    test('beyond ±3 SD the restricted method is used', () {
      final sd3 = lms.valueAt(3);
      final gap = sd3 - lms.valueAt(2);
      expect(lms.restrictedZ(sd3 + gap), closeTo(4, 1e-9));
      expect(lms.restrictedZ(lms.valueAt(2.5)), closeTo(2.5, 1e-9));
    });
  });

  group('WHO standards', () {
    test('a boy at the median weight and length at birth scores 0', () {
      final z = who.compute(sex: Sex.male, ageDays: 0, weightKg: 3.3464, heightCm: 49.8842);
      expect(z.weightForAge, closeTo(0, 1e-3));
      expect(z.heightForAge, closeTo(0, 1e-3));
    });

    // WHO's published charts (girls, weight-for-age and length-for-age, 12 months):
    // -3 SD .. +3 SD = 6.3 7.0 7.9 8.9 10.1 11.5 13.1 kg and 66.3 68.9 71.4 74.0 76.6 79.2 81.7 cm.
    test("reproduces WHO's printed SD lines for a 12-month-old girl", () {
      const kg = [6.3, 7.0, 7.9, 8.9, 10.1, 11.5, 13.1];
      const cm = [66.3, 68.9, 71.4, 74.0, 76.6, 79.2, 81.7];
      for (var i = 0; i < 7; i++) {
        final z = who.compute(sex: Sex.female, ageDays: 365, weightKg: kg[i], heightCm: cm[i]);
        // Published values are rounded to 0.1, so allow for that rounding.
        expect(z.weightForAge, closeTo(i - 3, 0.12), reason: '${kg[i]} kg');
        expect(z.heightForAge, closeTo(i - 3, 0.05), reason: '${cm[i]} cm');
      }
    });

    test('standing height under 2 years gets +0.7 cm, lying height from 2 years gets -0.7 cm', () {
      expect(WhoStandards.adjustHeight(80, 400, MeasuredPosition.standing), 80.7);
      expect(WhoStandards.adjustHeight(90, 800, MeasuredPosition.lying), closeTo(89.3, 1e-9));
      expect(WhoStandards.adjustHeight(90, 800, MeasuredPosition.standing), 90);
    });

    test('uses weight-for-length under 2 years and weight-for-height from 2 years', () {
      final under = who.compute(sex: Sex.male, ageDays: 700, weightKg: 10, heightCm: 80);
      final over = who.compute(sex: Sex.male, ageDays: 740, weightKg: 10, heightCm: 80, position: MeasuredPosition.standing);
      expect(under.weightForHeight, isNotNull);
      expect(over.weightForHeight, isNotNull);
      // 80 cm lying ≈ 79.3 cm standing, so the two tables give close but different answers.
      expect((under.weightForHeight! - over.weightForHeight!).abs(), lessThan(0.5));
    });

    test('interpolates between 0.1 cm rows', () {
      final a = who.compute(sex: Sex.female, ageDays: 300, weightKg: 8, heightCm: 70.0).weightForHeight!;
      final b = who.compute(sex: Sex.female, ageDays: 300, weightKg: 8, heightCm: 70.1).weightForHeight!;
      final mid = who.compute(sex: Sex.female, ageDays: 300, weightKg: 8, heightCm: 70.05).weightForHeight!;
      expect(mid, inInclusiveRange(b, a));
    });

    test('rejects ages outside 0–60 months', () {
      expect(() => who.compute(sex: Sex.male, ageDays: 1857, weightKg: 15), throwsRangeError);
    });

    test('weight-for-height is null outside the table range', () {
      final z = who.compute(sex: Sex.male, ageDays: 10, weightKg: 2, heightCm: 40);
      expect(z.weightForHeight, isNull);
    });

    test('flags biologically implausible values', () {
      final z = who.compute(sex: Sex.male, ageDays: 365, weightKg: 30, heightCm: 75);
      expect(z.implausible, containsAll(['weight-for-age', 'weight-for-height']));
    });

    test('ageInDays ignores the time of day', () {
      expect(WhoStandards.ageInDays(DateTime(2025, 1, 1, 23), DateTime(2025, 1, 2, 1)), 1);
    });

    test('reference curves rise with age', () {
      final median = who.curve(weight: true, sex: Sex.male, z: 0);
      expect(median, hasLength(61));
      expect(median.first.$2, closeTo(3.35, 0.01));
      expect(median.last.$2, greaterThan(median.first.$2 * 5));
    });
  });

  group('nutrition status', () {
    test('classifies moderate and severe undernutrition', () {
      final status = NutritionStatus.from(const ZScores(weightForAge: -2.4, heightForAge: -3.2, weightForHeight: -1.0, adjustedHeightCm: 70));
      expect(status.stunting, Severity.severe);
      expect(status.underweight, Severity.moderate);
      expect(status.wasting, Severity.normal);
      expect(status.overall, Severity.severe);
      expect(status.findings.first, 'Severe stunting');
    });

    test('severe wasting is listed first with a referral note', () {
      final status = NutritionStatus.from(const ZScores(weightForAge: -3.5, heightForAge: -1, weightForHeight: -3.4, adjustedHeightCm: 70));
      expect(status.findings.first, 'Severe wasting (SAM): refer for treatment');
    });

    test('detects growth faltering between visits before the child is underweight', () {
      const before = ZScores(weightForAge: 0.2, heightForAge: 0, weightForHeight: 0.1, adjustedHeightCm: 70);
      const now = ZScores(weightForAge: -0.6, heightForAge: 0, weightForHeight: -0.7, adjustedHeightCm: 72);
      final status = NutritionStatus.from(now, previous: before);
      expect(status.faltering, isTrue);
      expect(status.underweight, Severity.normal);
      expect(status.overall, Severity.moderate);
    });

    test('a healthy child is normal', () {
      final status = NutritionStatus.from(const ZScores(weightForAge: 0.1, heightForAge: -0.4, weightForHeight: 0.5, adjustedHeightCm: 70));
      expect(status.overall, Severity.normal);
      expect(status.findings, isEmpty);
    });
  });
}
