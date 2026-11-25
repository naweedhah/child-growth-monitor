import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../growth/assessment.dart';
import '../growth/lms.dart';
import '../growth/validation.dart';
import '../growth/who_standards.dart';
import '../providers.dart';
import 'format.dart';

/// Records one clinic or home visit. Z-scores are previewed live as the numbers are typed, and
/// biologically implausible values must be confirmed before they are saved.
class MeasurementFormScreen extends ConsumerStatefulWidget {
  const MeasurementFormScreen({super.key, required this.childId});

  final String childId;

  @override
  ConsumerState<MeasurementFormScreen> createState() => _MeasurementFormScreenState();
}

class _MeasurementFormScreenState extends ConsumerState<MeasurementFormScreen> {
  final _form = GlobalKey<FormState>();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _muac = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _date;
  MeasuredPosition? _position;
  var _saving = false;

  @override
  void dispose() {
    for (final c in [_weight, _height, _muac, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  ZScores? _preview(WhoStandards who, DateTime dob, Sex sex, DateTime date, MeasuredPosition position) {
    final weight = Validate.weightKg(_weight.text) == null ? Validate.parseDecimal(_weight.text) : null;
    final height = Validate.heightCm(_height.text) == null ? Validate.parseDecimal(_height.text) : null;
    final age = WhoStandards.ageInDays(dob, date);
    if ((weight == null && height == null) || age < 0 || age > WhoStandards.maxAgeDays) return null;
    return who.compute(sex: sex, ageDays: age, weightKg: weight, heightCm: height, position: position);
  }

  Future<void> _save(ZScores? z, MeasuredPosition position) async {
    if (!_form.currentState!.validate()) return;
    if (z != null && z.implausible.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Please re-check this measurement'),
          content: Text(
            'The ${z.implausible.join(' and ')} result is outside the range WHO considers biologically plausible. '
            'This usually means a typing or weighing error (for example 75 instead of 7.5).',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Fix it')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save anyway')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _saving = true);
    await ref.read(repositoryProvider).addMeasurement(
          childId: widget.childId,
          measuredOn: _date!,
          weightKg: Validate.parseDecimal(_weight.text),
          heightCm: Validate.parseDecimal(_height.text),
          position: position.name,
          muacCm: Validate.parseDecimal(_muac.text),
          notes: _notes.text,
        );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final entry = ref.watch(childProvider(widget.childId)).value;
    final who = ref.watch(whoStandardsProvider).value;
    final today = ref.watch(clockProvider)();
    if (entry == null || who == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final child = entry.record.child;
    final sex = child.sex == 'male' ? Sex.male : Sex.female;
    final date = _date ??= DateTime(today.year, today.month, today.day);
    // WHO: measure lying under 2 years, standing from 2 years.
    final position = _position ??
        (WhoStandards.ageInDays(child.dateOfBirth, date) < 731 ? MeasuredPosition.lying : MeasuredPosition.standing);
    final z = _preview(who, child.dateOfBirth, sex, date, position);
    final status = z == null ? null : NutritionStatus.from(z);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('Visit · ${child.name}')),
      body: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        onChanged: () => setState(() {}),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FormField<DateTime>(
              validator: (_) => Validate.measuredOn(_date, dob: child.dateOfBirth, today: today),
              builder: (field) => InkWell(
                onTap: () async {
                  final picked = await showDatePicker(context: context, initialDate: date, firstDate: child.dateOfBirth, lastDate: today);
                  if (picked != null) {
                    setState(() => _date = picked);
                    field.didChange(picked);
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(labelText: 'Visit date', border: const OutlineInputBorder(), errorText: field.errorText, suffixIcon: const Icon(Icons.calendar_today)),
                  child: Text('${dateFormat.format(date)}  (age ${formatAge(child.dateOfBirth, date)})'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _weight,
              decoration: const InputDecoration(labelText: 'Weight', suffixText: 'kg', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => Validate.weightKg(v) ??
                  (v!.trim().isEmpty && _height.text.trim().isEmpty ? 'Enter a weight or a length/height.' : null),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _height,
              decoration: const InputDecoration(labelText: 'Length / height', suffixText: 'cm', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: Validate.heightCm,
            ),
            const SizedBox(height: 8),
            SegmentedButton<MeasuredPosition>(
              segments: const [
                ButtonSegment(value: MeasuredPosition.lying, label: Text('Lying (length)')),
                ButtonSegment(value: MeasuredPosition.standing, label: Text('Standing (height)')),
              ],
              selected: {position},
              onSelectionChanged: (s) => setState(() => _position = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _muac,
              decoration: const InputDecoration(labelText: 'MUAC (optional)', suffixText: 'cm', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: Validate.muacCm,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
              maxLines: 2,
              maxLength: 300,
            ),
            if (z != null)
              Card(
                key: const Key('zPreview'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Result', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Wrap(spacing: 16, children: [
                      for (final (label, value) in [
                        ('WAZ', z.weightForAge),
                        ('HAZ', z.heightForAge),
                        ('WHZ', z.weightForHeight),
                      ])
                        Text('$label ${formatZ(value)}', style: TextStyle(color: zColor(value, scheme), fontWeight: FontWeight.w700)),
                    ]),
                    for (final f in status!.findings) Text('• $f'),
                    if (z.implausible.isNotEmpty)
                      Text('Check the ${z.implausible.join(' and ')}: outside WHO plausible range.', style: TextStyle(color: scheme.error)),
                  ]),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : () => _save(z, position),
              icon: const Icon(Icons.save),
              label: const Text('Save visit'),
            ),
          ],
        ),
      ),
    );
  }
}
