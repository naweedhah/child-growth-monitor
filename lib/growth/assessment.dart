import 'who_standards.dart';

enum Severity {
  normal,
  moderate,
  severe;

  bool operator >(Severity other) => index > other.index;
}

/// WHO nutritional status from z-scores, as used in child growth monitoring:
/// stunting (height-for-age), wasting (weight-for-height), underweight (weight-for-age).
class NutritionStatus {
  const NutritionStatus({
    required this.stunting,
    required this.wasting,
    required this.underweight,
    required this.overweight,
    required this.faltering,
  });

  factory NutritionStatus.from(ZScores z, {ZScores? previous}) {
    Severity below(double? value) => value == null
        ? Severity.normal
        : value < -3
            ? Severity.severe
            : value < -2
                ? Severity.moderate
                : Severity.normal;

    // Growth faltering: weight-for-age dropped by more than 0.67 SD (crossing a major centile
    // line) since the previous visit, even if the child is not yet underweight.
    final faltering = previous?.weightForAge != null &&
        z.weightForAge != null &&
        previous!.weightForAge! - z.weightForAge! > 0.67;

    return NutritionStatus(
      stunting: below(z.heightForAge),
      wasting: below(z.weightForHeight),
      underweight: below(z.weightForAge),
      overweight: z.weightForHeight != null && z.weightForHeight! > 2,
      faltering: faltering,
    );
  }

  final Severity stunting;
  final Severity wasting;
  final Severity underweight;
  final bool overweight;
  final bool faltering;

  /// The most urgent finding, which decides the badge colour and list order.
  Severity get overall {
    final worst = [stunting, wasting, underweight].reduce((a, b) => a > b ? a : b);
    if (worst == Severity.normal && (faltering || overweight)) return Severity.moderate;
    return worst;
  }

  /// Human-readable findings for the child's profile, most urgent first.
  List<String> get findings => [
        if (wasting == Severity.severe) 'Severe wasting (SAM): refer for treatment',
        if (wasting == Severity.moderate) 'Moderate wasting (MAM)',
        if (stunting == Severity.severe) 'Severe stunting',
        if (stunting == Severity.moderate) 'Stunting',
        if (underweight == Severity.severe) 'Severely underweight',
        if (underweight == Severity.moderate) 'Underweight',
        if (overweight) 'Overweight',
        if (faltering) 'Growth faltering since last visit',
      ];
}
