import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/src/core/calls/call_history_store.dart';
import 'package:matrix/src/core/calls/matrix_call_launcher.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/network/network_availability.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:provider/provider.dart';

/// Local Matrix / Element Call log; tap a row to call again.
///
/// On desktop, shows a master–detail layout: merged rows per counterparty (DM
/// user or group room) with the latest call summary; the detail pane lists all
/// calls with direction, time, and duration.
class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key, this.embedInParentScaffold = false});

  final bool embedInParentScaffold;

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

enum _CallKind { outgoing, incoming, missed }

_CallKind _classifyCallKind(CallHistoryEntry e) {
  if (e.direction == CallHistoryDirection.outgoing) {
    return _CallKind.outgoing;
  }
  final shortRing = e.duration.inSeconds < 3;
  final reason = e.endReason?.trim() ?? '';
  if (reason.isNotEmpty || shortRing) {
    return _CallKind.missed;
  }
  return _CallKind.incoming;
}

String _groupKeyForEntry(CallHistoryEntry e, String? selfUserId) {
  final self = selfUserId?.trim() ?? '';
  if (e.isDirectRoom) {
    for (final uid in e.participantUserIds) {
      final u = uid.trim();
      if (u.isNotEmpty && u != self) {
        return 'user:$u';
      }
    }
    return 'room:${e.roomId}';
  }
  return 'room:${e.roomId}';
}

String _displayTitleForGroup(String key, List<CallHistoryEntry> sortedDesc) {
  if (sortedDesc.isEmpty) return 'Unknown';
  if (key.startsWith('user:')) {
    final uid = key.substring('user:'.length);
    for (final e in sortedDesc) {
      final lab = e.participantLabels[uid];
      if (lab != null && lab.trim().isNotEmpty && lab != uid) {
        return lab.trim();
      }
    }
    return sortedDesc.first.roomName;
  }
  return sortedDesc.first.roomName;
}

class _CallHistoryGroup {
  const _CallHistoryGroup({
    required this.key,
    required this.displayTitle,
    required this.entries,
  });

  final String key;
  final String displayTitle;

  /// Newest first (same order as [CallHistoryStore.entries] per group).
  final List<CallHistoryEntry> entries;

  CallHistoryEntry get latest => entries.first;
}

List<_CallHistoryGroup> _buildGroups(
  List<CallHistoryEntry> entries,
  String? selfUserId,
) {
  final map = <String, List<CallHistoryEntry>>{};
  for (final e in entries) {
    final k = _groupKeyForEntry(e, selfUserId);
    map.putIfAbsent(k, () => []).add(e);
  }
  for (final list in map.values) {
    list.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }
  final groups =
      map.entries
          .map(
            (e) => _CallHistoryGroup(
              key: e.key,
              displayTitle: _displayTitleForGroup(e.key, e.value),
              entries: e.value,
            ),
          )
          .toList()
        ..sort((a, b) => b.latest.startedAt.compareTo(a.latest.startedAt));
  return groups;
}

String _two(int v) => v.toString().padLeft(2, '0');

String _formatInstant(DateTime utc) {
  final d = utc.toLocal();
  return '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';
}

String _formatDurationOnly(Duration dur) {
  if (dur.inHours >= 1) {
    return '${dur.inHours}h ${dur.inMinutes.remainder(60)}m';
  }
  if (dur.inMinutes >= 1) {
    return '${dur.inMinutes}m ${dur.inSeconds.remainder(60)}s';
  }
  return '${dur.inSeconds}s';
}

String _formatRange(CallHistoryEntry e) {
  final s = e.startedAt.toLocal();
  final t = e.endedAt.toLocal();
  String hm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
  final date = '${s.year}-${_two(s.month)}-${_two(s.day)}';
  return '$date · ${hm(s)}–${hm(t)} (${_formatDurationOnly(e.duration)})';
}

String _latestSubtitle(CallHistoryEntry e) {
  final kind = _classifyCallKind(e);
  final label = switch (kind) {
    _CallKind.outgoing => 'Outgoing',
    _CallKind.incoming => 'Incoming',
    _CallKind.missed => 'Missed',
  };
  final time = _formatInstant(e.startedAt);
  return '$label · $time';
}

IconData _kindIcon(_CallKind k, bool voiceOnly) {
  return switch (k) {
    _CallKind.outgoing => voiceOnly ? Icons.call_made : Icons.video_call,
    _CallKind.incoming => voiceOnly ? Icons.call_received : Icons.video_call,
    _CallKind.missed => Icons.phone_missed,
  };
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  String? _selfUserId;
  String? _selectedGroupKey;

  @override
  void initState() {
    super.initState();
    unawaited(CallHistoryStore.instance.ensureLoaded());
    unawaited(_loadSelfUserId());
  }

  Future<void> _loadSelfUserId() async {
    try {
      final id = await MatrixService().client.loggedInUserId();
      if (!mounted) return;
      setState(() => _selfUserId = id);
    } catch (_) {}
  }

  void _scheduleSelectionSync(List<_CallHistoryGroup> groups) {
    final desired = groups.isEmpty
        ? null
        : (_selectedGroupKey != null &&
              groups.any((g) => g.key == _selectedGroupKey))
        ? _selectedGroupKey
        : groups.first.key;
    if (desired == _selectedGroupKey) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (desired != _selectedGroupKey) {
        setState(() => _selectedGroupKey = desired);
      }
    });
  }

  _CallHistoryGroup? _selectedGroup(List<_CallHistoryGroup> groups) {
    if (groups.isEmpty) return null;
    if (_selectedGroupKey != null) {
      for (final g in groups) {
        if (g.key == _selectedGroupKey) return g;
      }
    }
    return groups.first;
  }

  String _participantsLine(CallHistoryEntry e) {
    if (e.participantLabels.isEmpty) return 'Participants: —';
    final parts = e.participantLabels.values.toList()..sort();
    if (parts.length <= 4) return parts.join(', ');
    return '${parts.take(3).join(', ')} +${parts.length - 3}';
  }

  Future<void> _onCallAgain(
    BuildContext context, {
    required String roomId,
    required String roomName,
    required bool isDirectRoom,
  }) async {
    final online = context.read<NetworkAvailability>().isOnline;
    if (!online) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect to the internet to place a call.'),
        ),
      );
      return;
    }
    await showMatrixCallOptionsSheet(
      context: context,
      roomId: roomId,
      roomName: roomName,
      isDirectRoom: isDirectRoom,
    );
  }

  Widget _buildMobileListTile(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    CallHistoryEntry e,
  ) {
    final incoming = e.direction == CallHistoryDirection.incoming;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer.withValues(alpha: 0.65),
        child: Icon(
          e.voiceOnly ? Icons.call : Icons.videocam,
          color: scheme.onPrimaryContainer,
          size: 22,
        ),
      ),
      title: Text(
        e.roomName,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                incoming ? Icons.call_received : Icons.call_made,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                incoming ? 'Incoming' : 'Outgoing',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (e.joinedExisting) ...[
                const SizedBox(width: 8),
                Text(
                  '· joined',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.tertiary,
                  ),
                ),
              ],
              if (e.isDirectRoom) ...[
                const SizedBox(width: 8),
                Text(
                  '· DM',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatRange(e),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (e.endReason != null && e.endReason!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              e.endReason!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.tertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 2),
          Text(
            _participantsLine(e),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      onTap: () => unawaited(
        _onCallAgain(
          context,
          roomId: e.roomId,
          roomName: e.roomName,
          isDirectRoom: e.isDirectRoom,
        ),
      ),
    );
  }

  Widget _buildMobileBody(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    List<CallHistoryEntry> entries,
  ) {
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No calls yet.\nStart a call from a chat or room info.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: entries.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.4),
      ),
      itemBuilder: (context, i) =>
          _buildMobileListTile(context, theme, scheme, entries[i]),
    );
  }

  Widget _buildDesktopBody(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    List<_CallHistoryGroup> groups,
  ) {
    _scheduleSelectionSync(groups);
    final selected = _selectedGroup(groups);

    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No calls yet.\nStart a call from a chat or room info.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    Widget listPane = Material(
      color: scheme.surfaceContainerLow,
      child: ListView.builder(
        itemCount: groups.length,
        itemBuilder: (context, i) {
          final g = groups[i];
          final latest = g.latest;
          final kind = _classifyCallKind(latest);
          final selectedHere = selected?.key == g.key;
          return ListTile(
            selected: selectedHere,
            selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.35),
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer.withValues(alpha: 0.65),
              child: Icon(
                _kindIcon(kind, latest.voiceOnly),
                color: scheme.onPrimaryContainer,
                size: 22,
              ),
            ),
            title: Text(
              g.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              _latestSubtitle(latest),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            onTap: () => setState(() => _selectedGroupKey = g.key),
          );
        },
      ),
    );

    Widget detailPane = Material(
      color: scheme.surface,
      child: selected == null
          ? Center(
              child: Text(
                'Select a conversation',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.displayTitle,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selected.latest.isDirectRoom
                            ? 'Direct message'
                            : 'Room · ${selected.latest.roomName}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => unawaited(
                          _onCallAgain(
                            context,
                            roomId: selected.latest.roomId,
                            roomName: selected.latest.roomName,
                            isDirectRoom: selected.latest.isDirectRoom,
                          ),
                        ),
                        icon: Icon(
                          selected.latest.voiceOnly
                              ? Icons.call
                              : Icons.video_call,
                        ),
                        label: const Text('Call again'),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: selected.entries.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.25),
                    ),
                    itemBuilder: (context, i) {
                      final e = selected.entries[i];
                      final kind = _classifyCallKind(e);
                      final label = switch (kind) {
                        _CallKind.outgoing => 'Outgoing',
                        _CallKind.incoming => 'Incoming',
                        _CallKind.missed => 'Missed',
                      };
                      return ListTile(
                        leading: Icon(
                          _kindIcon(kind, e.voiceOnly),
                          color: scheme.onSurfaceVariant,
                        ),
                        title: Text(label),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              _formatInstant(e.startedAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            Text(
                              'Duration: ${_formatDurationOnly(e.duration)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            if (e.endReason != null &&
                                e.endReason!.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                e.endReason!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.tertiary,
                                ),
                              ),
                            ],
                            if (e.joinedExisting) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Joined existing call',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.tertiary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        onTap: () => unawaited(
                          _onCallAgain(
                            context,
                            roomId: e.roomId,
                            roomName: e.roomName,
                            isDirectRoom: e.isDirectRoom,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 340, child: listPane),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
        Expanded(child: detailPane),
      ],
    );
  }

  Widget _buildEmbedHeader(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '> RECENT CALLS',
              style: theme.textTheme.labelLarge?.copyWith(
                color: MatrixTheme.matrixAccent,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
            onSelected: (v) async {
              if (v == 'clear') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear call history?'),
                    content: const Text(
                      'This only removes entries on this device.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  setState(() => _selectedGroupKey = null);
                  await CallHistoryStore.instance.clearAll();
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'clear', child: Text('Clear all')),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final embed = widget.embedInParentScaffold;
    final desktop = isDesktopTargetPlatform();

    final listContent = AnimatedBuilder(
      animation: CallHistoryStore.instance,
      builder: (context, _) {
        unawaited(CallHistoryStore.instance.ensureLoaded());
        final entries = CallHistoryStore.instance.entries;
        if (desktop && !embed) {
          final groups = _buildGroups(entries, _selfUserId);
          return _buildDesktopBody(context, theme, scheme, groups);
        }
        return _buildMobileBody(context, theme, scheme, entries);
      },
    );

    if (embed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildEmbedHeader(context, theme, scheme),
          Expanded(child: listContent),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'CALL HISTORY',
          style: TextStyle(fontFamily: MatrixTheme.fontFamily),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'clear') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear call history?'),
                    content: const Text(
                      'This only removes entries on this device.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  setState(() => _selectedGroupKey = null);
                  await CallHistoryStore.instance.clearAll();
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'clear', child: Text('Clear all')),
            ],
          ),
        ],
      ),
      body: listContent,
    );
  }
}
