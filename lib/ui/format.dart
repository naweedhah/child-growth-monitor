import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../growth/assessment.dart';

final dateFormat = DateFormat('d MMM yyyy');

/// "1 y 8 m", "5 m", "12 d": how clinic cards write a young child's age.
String formatAge(DateTime dob, DateTime on) {
  var months = (on.year - dob.year) * 12 + on.month - dob.month;
  if (on.day < dob.day) months--;
  if (months < 1) return '${on.difference(dob).inDays} d';
  if (months < 12) return '$months m';
  final years = months ~/ 12;
  final rest = months % 12;
  return rest == 0 ? '$years y' : '$years y $rest m';
}

String formatZ(double? z) => z == null ? '–' : (z >= 0 ? '+' : '') + z.toStringAsFixed(1);

/// Colours follow the usual growth-card convention: green normal, amber moderate, red severe.
Color severityColor(Severity? severity, ColorScheme scheme) => switch (severity) {
      Severity.severe => const Color(0xFFC62828),
      Severity.moderate => const Color(0xFFEF8F00),
      Severity.normal => const Color(0xFF2E7D32),
      null => scheme.outline,
    };

String severityLabel(Severity? severity) => switch (severity) {
      Severity.severe => 'Severe',
      Severity.moderate => 'Needs attention',
      Severity.normal => 'Normal',
      null => 'No measurements',
    };

/// Colour for a single z-score cell.
Color zColor(double? z, ColorScheme scheme) {
  if (z == null) return scheme.outline;
  if (z < -3 || z > 3) return severityColor(Severity.severe, scheme);
  if (z < -2 || z > 2) return severityColor(Severity.moderate, scheme);
  return severityColor(Severity.normal, scheme);
}
