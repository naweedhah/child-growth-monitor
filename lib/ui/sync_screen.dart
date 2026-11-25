import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/database.dart';
import '../providers.dart';
import '../sync/records.dart';
import '../sync/sync_engine.dart';
import 'format.dart';

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingChangesProvider).value ?? 0;
    final conflicts = ref.watch(conflictsProvider).value ?? const <SyncConflict>[];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(switch (status.phase) {
              SyncPhase.syncing => Icons.sync,
              SyncPhase.offline => Icons.cloud_off,
              SyncPhase.error => Icons.error_outline,
              SyncPhase.idle => Icons.cloud_done_outlined,
            }),
            title: Text(switch (status.phase) {
              SyncPhase.syncing => 'Syncing…',
              SyncPhase.offline => 'Offline',
              SyncPhase.error => 'Last sync failed',
              SyncPhase.idle => pending == 0 ? 'Up to date' : 'Waiting to upload',
            }),
            subtitle: Text([
              '$pending change(s) on this phone not uploaded yet',
              if (status.lastSyncedAt != null) 'Last synced ${dateFormat.add_Hm().format(status.lastSyncedAt!)}',
              if (status.message != null) status.message!,
            ].join('\n')),
          ),
          FilledButton.icon(
            onPressed: status.phase == SyncPhase.syncing ? null : () => ref.read(syncControllerProvider.notifier).syncNow(),
            icon: const Icon(Icons.sync),
            label: const Text('Sync now'),
          ),
          const SizedBox(height: 24),
          Text('Conflicts', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'A record was changed on this phone and on another device before they synced. Choose which version to keep; '
            'nothing is overwritten until you do.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (conflicts.isEmpty) const Text('None.'),
          for (final conflict in conflicts) _ConflictCard(conflict),
        ],
      ),
    );
  }
}

const _fieldLabels = {
  'name': 'Name',
  'sex': 'Sex',
  'dateOfBirth': 'Date of birth',
  'guardianName': 'Guardian',
  'guardianPhone': 'Phone',
  'area': 'Area',
  'notes': 'Notes',
  'deleted': 'Removed',
  'measuredOn': 'Visit date',
  'weightKg': 'Weight (kg)',
  'heightCm': 'Length/height (cm)',
  'position': 'Position',
  'muacCm': 'MUAC (cm)',
};

class _ConflictCard extends ConsumerWidget {
  const _ConflictCard(this.conflict);

  final SyncConflict conflict;

  Future<Map<String, Object?>?> _local(AppDatabase db) async {
    if (conflict.entity == 'child') {
      final c = await (db.select(db.children)..where((t) => t.id.equals(conflict.entityId))).getSingleOrNull();
      return c == null ? null : Records.childToRemote(c);
    }
    final m = await (db.select(db.measurements)..where((t) => t.id.equals(conflict.entityId))).getSingleOrNull();
    return m == null ? null : Records.measurementToRemote(m);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = SyncEngine.decodeData(conflict.remoteJson);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder(
          future: _local(ref.read(databaseProvider)),
          builder: (context, snapshot) {
            final local = snapshot.data ?? const <String, Object?>{};
            final changed = {...local.keys, ...remote.keys}
                .where((k) => k != 'updatedAt' && !Records.sameContent({k: local[k]}, {k: remote[k]}))
                .toList();
            String show(Object? v) => v is DateTime ? dateFormat.format(v) : (v ?? '–').toString();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${conflict.entity == 'child' ? 'Child' : 'Visit'}: ${show(local['name'] ?? remote['name'] ?? local['measuredOn'])}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Table(
                  columnWidths: const {0: IntrinsicColumnWidth()},
                  children: [
                    const TableRow(children: [Text(''), Text('This phone', style: TextStyle(fontWeight: FontWeight.w600)), Text('Other device', style: TextStyle(fontWeight: FontWeight.w600))]),
                    for (final k in changed)
                      TableRow(children: [Padding(padding: const EdgeInsets.only(right: 8), child: Text(_fieldLabels[k] ?? k)), Text(show(local[k])), Text(show(remote[k]))]),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton(
                    onPressed: () => ref.read(syncEngineProvider).resolve(conflict, keepMine: false),
                    child: const Text('Keep other device'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      await ref.read(syncEngineProvider).resolve(conflict, keepMine: true);
                      await ref.read(syncControllerProvider.notifier).syncNow();
                    },
                    child: const Text('Keep this phone'),
                  ),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }
}
