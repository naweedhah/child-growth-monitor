import 'dart:math' as math;

/// One row of a WHO LMS table.
class Lms {
  const Lms(this.l, this.m, this.s);

  /// Box-Cox power.
  final double l;

  /// Median.
  final double m;

  /// Coefficient of variation.
  final double s;

  /// The measurement that sits exactly [z] standard deviations from the median.
  double valueAt(double z) =>
      l == 0 ? m * math.exp(s * z) : m * math.pow(1 + l * s * z, 1 / l).toDouble();

  /// The LMS z-score: `((y / M)^L - 1) / (L * S)`.
  double rawZ(double y) => l == 0 ? math.log(y / m) / s : (math.pow(y / m, l) - 1) / (l * s);

  /// WHO's z-score for weight-based indicators. Beyond ±3 SD the LMS curve is skewed, so WHO
  /// measures the distance past ±3 SD in units of the gap between the 2 and 3 SD curves instead
  /// (the "restricted" method used by WHO Anthro and the igrowup macros).
  double restrictedZ(double y) {
    final z = rawZ(y);
    if (z > 3) {
      final sd3 = valueAt(3);
      return 3 + (y - sd3) / (sd3 - valueAt(2));
    }
    if (z < -3) {
      final sd3neg = valueAt(-3);
      return -3 + (y - sd3neg) / (valueAt(-2) - sd3neg);
    }
    return z;
  }

  /// Linear interpolation between two rows, for measurements that fall between table steps.
  static Lms lerp(Lms a, Lms b, double t) =>
      Lms(a.l + (b.l - a.l) * t, a.m + (b.m - a.m) * t, a.s + (b.s - a.s) * t);
}

enum Sex {
  male(1),
  female(2);

  const Sex(this.whoCode);

  /// The value WHO tables use in their `sex` column.
  final int whoCode;
}

/// An LMS table for one indicator, keyed by sex and an integer step (age in days, or length in
/// millimetres for the weight-for-length/height tables).
class LmsTable {
  LmsTable(this._rows, {required this.minKey, required this.maxKey});

  final Map<(Sex, int), Lms> _rows;
  final int minKey;
  final int maxKey;

  /// Parses a tab-separated WHO anthro file. [keyScale] turns the key column into an integer
  /// (1 for age in days, 10 for length/height in cm with one decimal).
  factory LmsTable.parse(String tsv, {int keyScale = 1}) {
    final rows = <(Sex, int), Lms>{};
    var minKey = 1 << 30;
    var maxKey = -1;
    for (final line in tsv.split('\n').skip(1)) {
      final cols = line.trim().split(RegExp(r'\s+'));
      if (cols.length < 5) continue;
      final sex = cols[0] == '1' ? Sex.male : Sex.female;
      final key = (double.parse(cols[1]) * keyScale).round();
      rows[(sex, key)] = Lms(double.parse(cols[2]), double.parse(cols[3]), double.parse(cols[4]));
      minKey = math.min(minKey, key);
      maxKey = math.max(maxKey, key);
    }
    if (rows.isEmpty) throw const FormatException('Empty LMS table');
    return LmsTable(rows, minKey: minKey, maxKey: maxKey);
  }

  bool covers(int key) => key >= minKey && key <= maxKey;

  /// Exact row lookup; null when [key] is outside the table.
  Lms? at(Sex sex, int key) => _rows[(sex, key)];

  /// Lookup for a fractional key (e.g. 74.25 cm → 742.5 mm), interpolating between rows.
  Lms? interpolated(Sex sex, double key) {
    final lower = key.floor();
    final upper = key.ceil();
    final a = at(sex, lower);
    final b = at(sex, upper);
    if (a == null || b == null) return null;
    return lower == upper ? a : Lms.lerp(a, b, key - lower);
  }
}
