import 'lms.dart';

/// Which table a weight-for-length/height z-score came from.
enum WflhTable { weightForLength, weightForHeight }

/// How the length/height was taken. WHO uses recumbent length under 2 years and standing
/// height from 2 years; the two differ by about 0.7 cm.
enum MeasuredPosition { lying, standing }

/// The z-scores for one measurement. A null value means it could not be computed (for example
/// weight-for-height outside the 45–120 cm range), never that it is zero.
class ZScores {
  const ZScores({this.weightForAge, this.heightForAge, this.weightForHeight, required this.adjustedHeightCm});

  final double? weightForAge;
  final double? heightForAge;
  final double? weightForHeight;

  /// Length/height after WHO's 0.7 cm lying/standing correction.
  final double? adjustedHeightCm;

  /// WHO marks these as biologically implausible: almost certainly a measuring or typing error.
  List<String> get implausible => [
        if (weightForAge != null && (weightForAge! < -6 || weightForAge! > 5)) 'weight-for-age',
        if (heightForAge != null && (heightForAge! < -6 || heightForAge! > 6)) 'height-for-age',
        if (weightForHeight != null && (weightForHeight! < -5 || weightForHeight! > 5)) 'weight-for-height',
      ];
}

/// WHO Child Growth Standards (0–5 years) computed the way WHO Anthro does.
class WhoStandards {
  WhoStandards({required this.weightForAge, required this.lengthForAge, required this.weightForLength, required this.weightForHeight});

  /// Builds the standards from the four tab-separated files in `assets/who/`.
  factory WhoStandards.fromTsv({required String wei, required String len, required String wfl, required String wfh}) =>
      WhoStandards(
        weightForAge: LmsTable.parse(wei),
        lengthForAge: LmsTable.parse(len),
        weightForLength: LmsTable.parse(wfl, keyScale: 10),
        weightForHeight: LmsTable.parse(wfh, keyScale: 10),
      );

  final LmsTable weightForAge;
  final LmsTable lengthForAge;
  final LmsTable weightForLength;
  final LmsTable weightForHeight;

  /// The standards cover birth to 60 completed months.
  static const maxAgeDays = 1856;

  /// Age in completed days, as WHO counts it.
  static int ageInDays(DateTime dob, DateTime measuredOn) =>
      DateTime.utc(measuredOn.year, measuredOn.month, measuredOn.day)
          .difference(DateTime.utc(dob.year, dob.month, dob.day))
          .inDays;

  /// Converts a standing height to length (or the reverse) so it matches the table for the age.
  static double adjustHeight(double cm, int ageDays, MeasuredPosition position) {
    if (ageDays < 731 && position == MeasuredPosition.standing) return cm + 0.7;
    if (ageDays >= 731 && position == MeasuredPosition.lying) return cm - 0.7;
    return cm;
  }

  ZScores compute({
    required Sex sex,
    required int ageDays,
    double? weightKg,
    double? heightCm,
    MeasuredPosition position = MeasuredPosition.lying,
  }) {
    if (ageDays < 0 || ageDays > maxAgeDays) {
      throw RangeError.range(ageDays, 0, maxAgeDays, 'ageDays', 'WHO standards cover 0–60 months');
    }
    final height = heightCm == null ? null : adjustHeight(heightCm, ageDays, position);

    double? waz;
    if (weightKg != null) waz = weightForAge.at(sex, ageDays)?.restrictedZ(weightKg);

    double? haz;
    if (height != null) haz = lengthForAge.at(sex, ageDays)?.rawZ(height);

    double? whz;
    if (weightKg != null && height != null) {
      final table = ageDays < 731 ? weightForLength : weightForHeight;
      // Table keys are millimetres; WHO interpolates between the 0.1 cm rows.
      whz = table.interpolated(sex, height * 10)?.restrictedZ(weightKg);
    }

    return ZScores(weightForAge: waz, heightForAge: haz, weightForHeight: whz, adjustedHeightCm: height);
  }

  /// Points on a standard-deviation curve of weight-for-age or length/height-for-age, one per
  /// month, for drawing reference lines on a growth chart.
  List<(double month, double value)> curve({required bool weight, required Sex sex, required double z}) {
    final table = weight ? weightForAge : lengthForAge;
    return [
      for (var month = 0; month <= 60; month++)
        if (table.at(sex, (month * 30.4375).round()) case final lms?) (month.toDouble(), lms.valueAt(z)),
    ];
  }
}
