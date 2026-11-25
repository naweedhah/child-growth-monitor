import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../growth/lms.dart';
import '../providers.dart';
import 'format.dart';
import 'growth_chart.dart';
import 'widgets.dart';

class ChildScreen extends ConsumerStatefulWidget {
  const ChildScreen({super.key, required this.childId});

  final String childId;

  @override
  ConsumerState<ChildScreen> createState() => _ChildScreenState();
}

class _ChildScreenState extends ConsumerState<ChildScreen> {
  var _weightChart = true;

  Future<void> _delete(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text('The child and all their measurements are removed from your caseload on every device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(repositoryProvider).deleteChild(widget.childId);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final entry = ref.watch(childProvider(widget.childId));
    final who = ref.watch(whoStandardsProvider).value;
    final today = ref.watch(clockProvider)();
    final theme = Theme.of(context);

    final c = entry.value;
    if (c == null || who == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: entry.isLoading ? const CircularProgressIndicator() : const Text('Child not found')));
    }
    final child = c.record.child;
    final z = c.latestZ;

    return Scaffold(
      appBar: AppBar(
        title: Text(child.name),
        actions: [
          IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit), onPressed: () => context.push('/children/${child.id}/edit')),
          IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(child.name)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/children/${child.id}/measure'),
        icon: const Icon(Icons.monitor_weight_outlined),
        label: const Text('Record visit'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${child.sex == 'male' ? 'Boy' : 'Girl'} · ${formatAge(child.dateOfBirth, today)} · born ${dateFormat.format(child.dateOfBirth)}\n'
                  '${child.guardianName}${child.guardianPhone == null ? '' : ' · ${child.guardianPhone}'} · ${child.area}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              SeverityBadge(c.severity),
            ],
          ),
          const SizedBox(height: 16),
          if (z != null) ...[
            Row(
              children: [
                _ZCell(label: 'Weight-for-age', z: z.weightForAge),
                _ZCell(label: 'Height-for-age', z: z.heightForAge),
                _ZCell(label: 'Weight-for-height', z: z.weightForHeight),
              ],
            ),
            const SizedBox(height: 12),
            for (final finding in c.status!.findings)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: severityColor(c.severity, theme.colorScheme)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(finding, style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
              ),
            if (c.record.latest?.muacCm case final muac?)
              Text('MUAC ${muac.toStringAsFixed(1)} cm${muac < 11.5 ? ' (below 11.5 cm: severe acute malnutrition screen)' : muac < 12.5 ? ' (11.5–12.5 cm: moderate)' : ''}'),
          ] else
            const Text('No measurements yet. Tap “Record visit” to add the first one.'),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Weight-for-age')),
              ButtonSegment(value: false, label: Text('Length/height')),
            ],
            selected: {_weightChart},
            onSelectionChanged: (s) => setState(() => _weightChart = s.first),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: GrowthChart(
              who: who,
              sex: child.sex == 'male' ? Sex.male : Sex.female,
              dob: child.dateOfBirth,
              measurements: c.record.measurements,
              weight: _weightChart,
            ),
          ),
          const SizedBox(height: 8),
          Text('Lines: WHO median (green), ±2 SD (amber), ±3 SD (red, dashed).', style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Text('Visits', style: theme.textTheme.titleMedium),
          for (final (i, m) in c.record.measurements.indexed.toList().reversed)
            Dismissible(
              key: ValueKey(m.id),
              direction: DismissDirection.endToStart,
              background: Container(color: theme.colorScheme.errorContainer, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), child: const Icon(Icons.delete)),
              confirmDismiss: (_) async => await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete this visit?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                  ],
                ),
              ),
              onDismissed: (_) => ref.read(repositoryProvider).deleteMeasurement(m.id),
              child: Builder(builder: (context) {
                final visitZ = zScoresFor(who, c.record, i);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${dateFormat.format(m.measuredOn)} · ${formatAge(child.dateOfBirth, m.measuredOn)}'),
                  subtitle: Text([
                    if (m.weightKg != null) '${m.weightKg} kg',
                    if (m.heightCm != null) '${m.heightCm} cm ${m.position}',
                    if (m.muacCm != null) 'MUAC ${m.muacCm} cm',
                    if (m.dirty) 'not synced yet',
                  ].join(' · ')),
                  trailing: Text(
                    'WAZ ${formatZ(visitZ?.weightForAge)}\nHAZ ${formatZ(visitZ?.heightForAge)}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall,
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class _ZCell extends StatelessWidget {
  const _ZCell({required this.label, required this.z});

  final String label;
  final double? z;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = zColor(z, scheme);
    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(children: [
            Text(formatZ(z), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

