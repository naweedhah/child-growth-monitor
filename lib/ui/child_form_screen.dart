import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../data/database.dart';
import '../growth/validation.dart';
import '../providers.dart';
import 'format.dart';

/// Register a new child, or edit one when [childId] is given.
class ChildFormScreen extends ConsumerStatefulWidget {
  const ChildFormScreen({super.key, this.childId});

  final String? childId;

  @override
  ConsumerState<ChildFormScreen> createState() => _ChildFormScreenState();
}

class _ChildFormScreenState extends ConsumerState<ChildFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _guardian = TextEditingController();
  final _phone = TextEditingController();
  final _area = TextEditingController();
  final _notes = TextEditingController();
  String _sex = 'female';
  DateTime? _dob;
  var _loaded = false;
  var _saving = false;

  void _load(Child c) {
    if (_loaded) return;
    _loaded = true;
    _name.text = c.name;
    _guardian.text = c.guardianName;
    _phone.text = c.guardianPhone ?? '';
    _area.text = c.area;
    _notes.text = c.notes ?? '';
    _sex = c.sex;
    _dob = c.dateOfBirth;
  }

  @override
  void dispose() {
    for (final c in [_name, _guardian, _phone, _area, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDob() async {
    final today = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? today.subtract(const Duration(days: 180)),
      firstDate: today.subtract(const Duration(days: 1856)),
      lastDate: today,
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final id = await ref.read(repositoryProvider).saveChild(
          id: widget.childId,
          name: _name.text,
          sex: _sex,
          dateOfBirth: _dob!,
          guardianName: _guardian.text,
          guardianPhone: _phone.text.replaceAll(RegExp(r'[\s-]'), ''),
          area: _area.text,
          notes: _notes.text,
        );
    if (!mounted) return;
    if (widget.childId == null) {
      context.pushReplacement('/children/$id');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.childId != null) {
      final existing = ref.watch(childProvider(widget.childId!)).value?.record.child;
      if (existing == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      _load(existing);
    }
    final today = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(title: Text(widget.childId == null ? 'Register child' : 'Edit child')),
      body: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: "Child's name", border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.words,
              validator: (v) => Validate.name(v),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'female', label: Text('Girl'), icon: Icon(Icons.girl)),
                ButtonSegment(value: 'male', label: Text('Boy'), icon: Icon(Icons.boy)),
              ],
              selected: {_sex},
              onSelectionChanged: (s) => setState(() => _sex = s.first),
            ),
            const SizedBox(height: 16),
            FormField<DateTime>(
              initialValue: _dob,
              validator: (_) => Validate.dateOfBirth(_dob, today: today),
              builder: (field) => InkWell(
                onTap: () async {
                  await _pickDob();
                  field.didChange(_dob);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Date of birth',
                    border: const OutlineInputBorder(),
                    errorText: field.errorText,
                    suffixIcon: const Icon(Icons.calendar_today),
                  ),
                  child: Text(_dob == null ? 'Select' : '${dateFormat.format(_dob!)}  (${formatAge(_dob!, today)})'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _guardian,
              decoration: const InputDecoration(labelText: 'Mother / guardian', border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.words,
              validator: (v) => Validate.name(v, label: 'Guardian name'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Guardian phone (optional)', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
              validator: Validate.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _area,
              decoration: const InputDecoration(labelText: 'Village / GN division', border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.words,
              validator: (v) => Validate.name(v, label: 'Area'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
