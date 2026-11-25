import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../data/database.dart';
import '../growth/lms.dart';
import '../growth/who_standards.dart';

/// A growth chart in the style of the child health record: WHO reference curves at
/// -3, -2, 0, +2 and +3 SD, with the child's measurements plotted on top.
class GrowthChart extends StatelessWidget {
  const GrowthChart({super.key, required this.who, required this.sex, required this.dob, required this.measurements, required this.weight});

  final WhoStandards who;
  final Sex sex;
  final DateTime dob;
  final List<Measurement> measurements;

  /// Weight-for-age when true, length/height-for-age otherwise.
  final bool weight;

  static const _lines = <(double z, Color color, String label)>[
    (3, Color(0xFFC62828), '+3'),
    (2, Color(0xFFEF8F00), '+2'),
    (0, Color(0xFF2E7D32), '0'),
    (-2, Color(0xFFEF8F00), '-2'),
    (-3, Color(0xFFC62828), '-3'),
  ];

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final m in measurements)
        if ((weight ? m.weightKg : m.heightCm) case final value?)
          FlSpot(WhoStandards.ageInDays(dob, m.measuredOn) / 30.4375,
              weight ? value : WhoStandards.adjustHeight(value, WhoStandards.ageInDays(dob, m.measuredOn), m.position == 'standing' ? MeasuredPosition.standing : MeasuredPosition.lying)),
    ];
    // Show from birth to a little past the latest measurement (at least 12 months).
    final latest = points.isEmpty ? 0.0 : points.map((p) => p.x).reduce((a, b) => a > b ? a : b);
    final maxX = (((latest + 6) / 6).ceil() * 6).clamp(12, 60).toDouble();

    List<FlSpot> curve(double z) => [
          for (final (month, value) in who.curve(weight: weight, sex: sex, z: z))
            if (month <= maxX) FlSpot(month, value),
        ];

    // Round the y range to whole grid steps so axis labels never collide.
    final step = weight ? 2.0 : 10.0;
    final top = curve(3).map((p) => p.y).fold<double>(0, (a, b) => a > b ? a : b);
    final bottom = curve(-3).map((p) => p.y).fold<double>(double.infinity, (a, b) => a < b ? a : b);
    final ys = [top, bottom, ...points.map((p) => p.y)];
    final maxY = (ys.reduce((a, b) => a > b ? a : b) / step).ceil() * step;
    final minY = (ys.reduce((a, b) => a < b ? a : b) / step).floor() * step;

    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '${weight ? 'Weight' : 'Length or height'}-for-age chart with ${points.length} measurements',
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          clipData: const FlClipData.all(),
          gridData: FlGridData(drawVerticalLine: true, verticalInterval: 6, horizontalInterval: weight ? 2 : 10),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              axisNameSize: 22,
              axisNameWidget: const Text('Age (months)'),
              sideTitles: SideTitles(showTitles: true, interval: 6, reservedSize: 24, getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 11))),
            ),
            leftTitles: AxisTitles(
              axisNameSize: 22,
              axisNameWidget: Text(weight ? 'Weight (kg)' : 'Length/height (cm)'),
              sideTitles: SideTitles(showTitles: true, reservedSize: 34, interval: weight ? 2 : 10, getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 11))),
            ),
          ),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            for (final (z, color, _) in _lines)
              LineChartBarData(
                spots: curve(z),
                isCurved: true,
                color: color.withValues(alpha: 0.8),
                barWidth: z == 0 ? 2 : 1.2,
                dotData: const FlDotData(show: false),
                dashArray: z.abs() == 3 ? [6, 4] : null,
              ),
            LineChartBarData(
              spots: points,
              color: scheme.primary,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, _, _) => FlDotCirclePainter(radius: 4, color: scheme.primary, strokeWidth: 2, strokeColor: scheme.surface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
