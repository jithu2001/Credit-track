import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../company/domain/company.dart';
import '../../company/presentation/company_providers.dart';
import '../data/sync_health_repository.dart';

class SyncHealthScreen extends ConsumerWidget {
  const SyncHealthScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(tallyConnectionsProvider)
      ..invalidate(recentSyncLogsProvider)
      ..invalidate(companiesProvider);
    await ref.read(recentSyncLogsProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(tallyConnectionsProvider);
    final companies = ref.watch(companiesProvider);
    final logs = ref.watch(recentSyncLogsProvider);
    final names = {for (final c in companies.value ?? const <Company>[]) c.id: c.companyName};
    return Scaffold(
      appBar: AppBar(title: const Text('Sync health')),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ContentWidth(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Insets.l),
            children: [
              _Section(
                title: 'Tally PC',
                child: switch (connections) {
                  AsyncValue(:final value?) when value.isEmpty => const ListTile(
                    title: Text('No sync service has connected yet'),
                  ),
                  AsyncValue(:final value?) => Column(
                    children: [
                      for (final c in value)
                        ListTile(
                          leading: Icon(_isLive(c) ? Icons.computer_rounded : Icons.desktop_access_disabled_rounded),
                          title: Text(c.hostname ?? c.machineIdentifier),
                          subtitle: Text(
                            [
                              _isLive(c) ? 'Online' : 'Not seen recently',
                              if (c.lastSeenAt != null) 'last seen ${timeAgo(c.lastSeenAt!)}',
                              if (c.appVersion != null) 'v${c.appVersion}',
                            ].join(' · '),
                          ),
                        ),
                    ],
                  ),
                  AsyncValue(:final error?) => ErrorState(error: error, onRetry: () => ref.invalidate(tallyConnectionsProvider)),
                  _ => const SkeletonTile(),
                },
              ),
              _Section(
                title: 'Companies',
                child: switch (companies) {
                  AsyncValue(:final value?) => Column(
                    children: [
                      for (final c in value)
                        ListTile(
                          leading: _StatusDot(ok: c.syncStatus == 'SYNCED'),
                          title: Text(c.companyName),
                          subtitle: Text(
                            [
                              _statusLabel(c.syncStatus),
                              if (c.lastSyncAt != null) 'last success ${timeAgo(c.lastSyncAt!)}',
                            ].join(' · '),
                          ),
                        ),
                    ],
                  ),
                  AsyncValue(:final error?) => ErrorState(error: error, onRetry: () => ref.invalidate(companiesProvider)),
                  _ => const SkeletonTile(),
                },
              ),
              _Section(
                title: 'Recent sync runs',
                child: switch (logs) {
                  AsyncValue(:final value?) when value.isEmpty => const ListTile(title: Text('No sync runs recorded yet')),
                  AsyncValue(:final value?) => Column(
                    children: [
                      for (final (i, l) in value.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _LogTile(entry: l, companyName: l.companyId == null ? 'All companies' : names[l.companyId]),
                      ],
                    ],
                  ),
                  AsyncValue(:final error?) => ErrorState(error: error, onRetry: () => ref.invalidate(recentSyncLogsProvider)),
                  _ => const Column(children: [SkeletonTile(), SkeletonTile()]),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sync service writes `online` on every run; if it hasn't been heard
/// from for a while (PC off, service stopped), don't keep saying online.
const _liveWindow = Duration(minutes: 15);

bool _isLive(TallyConnection c) =>
    c.status == 'online' && c.lastSeenAt != null && DateTime.now().difference(c.lastSeenAt!) < _liveWindow;

String _statusLabel(String s) => switch (s) {
  'SYNCED' => 'Synced',
  'SYNCING' => 'Syncing',
  'PENDING' => 'Waiting for first sync',
  'TALLY_OFFLINE' => 'Tally offline',
  'CLOUD_OFFLINE' => 'PC offline (no internet)',
  'AUTH_ERROR' => 'Not authorised',
  'SYNC_ERROR' => 'Sync error',
  'COMPANY_NOT_OPEN' => 'Company not open in Tally',
  'DISABLED' => 'Sync disabled',
  _ => s,
};

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: context.text.titleMedium),
          const SizedBox(height: Insets.s),
          Card.outlined(child: child),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.ok});

  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Icon(
      ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
      color: ok ? context.semantic.credit : context.semantic.warning,
      semanticLabel: ok ? 'OK' : 'Needs attention',
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry, required this.companyName});

  final SyncLogEntry entry;
  final String? companyName;

  @override
  Widget build(BuildContext context) {
    final ok = entry.status == 'success';
    final duration = entry.completedAt?.difference(entry.startedAt);
    final counts =
        'Shops ${entry.shopsProcessed} · vouchers ${entry.transactionsFetched} · '
        '+${entry.recordsCreated} ~${entry.recordsUpdated} −${entry.recordsDeleted}'
        '${entry.recordsFailed > 0 ? ' · ${entry.recordsFailed} failed' : ''}';
    return ListTile(
      leading: _StatusDot(ok: ok),
      title: Text('${formatDateTime(entry.startedAt)} · ${entry.status}${entry.mode == null ? '' : ' (${entry.mode})'}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (companyName != null) Text(companyName!),
          Text(counts),
          if (duration != null) Text('Took ${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s'),
          if (_errorText(entry) case final error?) Text(error, style: TextStyle(color: context.colors.error)),
        ],
      ),
      isThreeLine: true,
    );
  }
}

/// "CODE: message", or null when the sync service left both blank.
String? _errorText(SyncLogEntry e) {
  final parts = [e.errorCode, e.errorMessage].whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty);
  return parts.isEmpty ? null : parts.join(': ');
}
