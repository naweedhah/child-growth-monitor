import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../growth/assessment.dart';
import '../providers.dart';
import 'format.dart';
import 'widgets.dart';

enum CaseloadFilter { all, attention, overdue }

/// Days after which a child under 5 is overdue for a growth check (monthly under 1 year,
/// at least every two months after that in the Sri Lankan CHDR schedule).
const overdueAfterDays = 60;

class CaseloadScreen extends ConsumerStatefulWidget {
  const CaseloadScreen({super.key});

  @override
  ConsumerState<CaseloadScreen> createState() => _CaseloadScreenState();
}

class _CaseloadScreenState extends ConsumerState<CaseloadScreen> {
  var _query = '';
  var _filter = CaseloadFilter.all;

  bool _matches(ChildStatus c, DateTime today) {
    final child = c.record.child;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty &&
        !child.name.toLowerCase().contains(q) &&
        !child.area.toLowerCase().contains(q) &&
        !child.guardianName.toLowerCase().contains(q)) {
      return false;
    }
    return switch (_filter) {
      CaseloadFilter.all => true,
      CaseloadFilter.attention => c.severity == Severity.moderate || c.severity == Severity.severe,
      CaseloadFilter.overdue =>
        c.record.latest == null || today.difference(c.record.latest!.measuredOn).inDays > overdueAfterDays,
    };
  }

  @override
  Widget build(BuildContext context) {
    final caseload = ref.watch(caseloadProvider);
    final today = ref.watch(clockProvider)();
    final status = ref.watch(syncControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My caseload'),
        actions: [
          const SyncButton(),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(firebaseAuthProvider).signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/children/new'),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Register child'),
      ),
      body: Column(
        children: [
          if (status.phase == SyncPhase.offline)
            MaterialBanner(
              content: const Text('Offline. Everything you record is saved on this phone and uploads when you reconnect.'),
              leading: const Icon(Icons.cloud_off),
              actions: [TextButton(onPressed: () => ref.read(syncControllerProvider.notifier).syncNow(), child: const Text('Retry'))],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name, guardian or area',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final (filter, label) in const [
                  (CaseloadFilter.all, 'All'),
                  (CaseloadFilter.attention, 'Needs attention'),
                  (CaseloadFilter.overdue, 'Overdue visit'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: caseload.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load the caseload: $e')),
              data: (children) {
                final visible = children.where((c) => _matches(c, today)).toList();
                if (children.isEmpty) {
                  return const _Empty('No children yet', 'Tap “Register child” to add the first one.');
                }
                if (visible.isEmpty) return const _Empty('No matches', 'Try another search or filter.');
                return RefreshIndicator(
                  onRefresh: () => ref.read(syncControllerProvider.notifier).syncNow(),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _ChildTile(visible[i], today: today),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChildTile extends StatelessWidget {
  const _ChildTile(this.c, {required this.today});

  final ChildStatus c;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final child = c.record.child;
    final latest = c.record.latest;
    final overdue = latest == null || today.difference(latest.measuredOn).inDays > overdueAfterDays;
    final theme = Theme.of(context);

    return ListTile(
      onTap: () => context.push('/children/${child.id}'),
      leading: CircleAvatar(
        backgroundColor: severityColor(c.severity, theme.colorScheme).withValues(alpha: 0.15),
        child: Icon(child.sex == 'male' ? Icons.boy : Icons.girl, color: severityColor(c.severity, theme.colorScheme)),
      ),
      title: Text(child.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${formatAge(child.dateOfBirth, today)} · ${child.area}\n'
        '${latest == null ? 'Never measured' : 'Last visit ${dateFormat.format(latest.measuredOn)}'}${overdue ? ' · overdue' : ''}',
      ),
      isThreeLine: true,
      trailing: SeverityBadge(c.severity),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.title, this.message);

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ]),
        ),
      );
}
