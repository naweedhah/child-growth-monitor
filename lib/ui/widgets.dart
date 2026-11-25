import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../growth/assessment.dart';
import '../providers.dart';
import 'format.dart';

class SeverityBadge extends StatelessWidget {
  const SeverityBadge(this.severity, {super.key});

  final Severity? severity;

  @override
  Widget build(BuildContext context) {
    final color = severityColor(severity, Theme.of(context).colorScheme);
    return Semantics(
      label: 'Status: ${severityLabel(severity)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(severityLabel(severity), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      ),
    );
  }
}

/// App-bar button showing sync state; opens the sync screen.
class SyncButton extends ConsumerWidget {
  const SyncButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingChangesProvider).value ?? 0;
    final conflicts = ref.watch(conflictsProvider).value?.length ?? 0;

    final (icon, tooltip) = switch (status.phase) {
      SyncPhase.syncing => (Icons.sync, 'Syncing…'),
      SyncPhase.offline => (Icons.cloud_off, 'Offline: $pending change(s) saved on this phone'),
      SyncPhase.error => (Icons.sync_problem, 'Sync failed'),
      SyncPhase.idle when conflicts > 0 => (Icons.sync_problem, '$conflicts conflict(s) to review'),
      SyncPhase.idle when pending > 0 => (Icons.cloud_upload_outlined, '$pending change(s) waiting to upload'),
      SyncPhase.idle => (Icons.cloud_done_outlined, 'All changes synced'),
    };

    return IconButton(
      tooltip: tooltip,
      onPressed: () => context.push('/sync'),
      icon: Badge(
        isLabelVisible: pending + conflicts > 0,
        label: Text('${pending + conflicts}'),
        backgroundColor: conflicts > 0 ? Theme.of(context).colorScheme.error : null,
        child: Icon(icon),
      ),
    );
  }
}
