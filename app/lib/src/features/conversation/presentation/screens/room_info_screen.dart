import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:matrix/src/core/desktop/desktop_esc_scope.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:matrix/src/core/open_in_app_url.dart';
import 'package:matrix/src/core/timeline_local_hidden_store.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/conversation/presentation/widgets/link_preview_cards.dart';
import 'package:matrix/src/features/conversation/domain/services/conversation_service.dart';
import 'package:matrix/src/features/conversation/presentation/widgets/attachment_viewer.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix_sdk/matrix_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart';

/// Pop result from [RoomInfoScreen]: leaving the room, or focusing a timeline event.
class RoomInfoNavResult {
  const RoomInfoNavResult({this.leftRoom = false, this.focusEventId});

  final bool leftRoom;
  final String? focusEventId;
}

/// Room info uses the same [ThemeData] / [ColorScheme] patterns as the chat
/// listing and conversation screens (primary borders, textTheme,
/// surfaceContainerHighest panels).
abstract final class _RoomInfoStyles {
  static const EdgeInsets listPadding = EdgeInsets.all(16);
  static const EdgeInsets blockPadding = EdgeInsets.all(16);

  static TextStyle prompt(ThemeData t) => t.textTheme.labelMedium!.copyWith(
    color: t.colorScheme.primary,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.35,
  );

  static TextStyle sectionHeader(ThemeData t) => t.textTheme.titleLarge!;

  static TextStyle bodyMuted(ThemeData t) => t.textTheme.bodyMedium!.copyWith(
    color: t.colorScheme.onSurface.withValues(alpha: 0.88),
    height: 1.45,
  );

  static TextStyle captionMuted(ThemeData t) => t.textTheme.bodySmall!.copyWith(
    color: t.colorScheme.onSurface.withValues(alpha: 0.72),
    height: 1.35,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static Widget sectionDivider(ThemeData t) => Divider(
    height: 1,
    thickness: 1,
    color: t.colorScheme.outline.withValues(alpha: 0.35),
  );
}

IconData _roomFileIcon(RoomMessageKind k) {
  switch (k) {
    case RoomMessageKind.image:
      return Icons.image_outlined;
    case RoomMessageKind.video:
      return Icons.video_file_outlined;
    case RoomMessageKind.audio:
      return Icons.audio_file_outlined;
    case RoomMessageKind.file:
      return Icons.insert_drive_file_outlined;
    case RoomMessageKind.text:
    case RoomMessageKind.poll:
      return Icons.poll_outlined;
    case RoomMessageKind.other:
      return Icons.attach_file_outlined;
  }
}

/// Full-screen room details: manifest + members; media and actions in bottom sheets.
class RoomInfoScreen extends StatefulWidget {
  const RoomInfoScreen({super.key, required this.roomId, this.initialTitle});

  final String roomId;
  final String? initialTitle;

  @override
  State<RoomInfoScreen> createState() => _RoomInfoScreenState();
}

class _RoomInfoScreenState extends State<RoomInfoScreen> {
  final _service = ConversationService(matrixService: MatrixService());

  RoomDetails? _details;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _service.getRoomDetails(widget.roomId);
    r.fold(
      (d) {
        if (!mounted) return;
        setState(() {
          _details = d;
          _loading = false;
        });
      },
      (f) {
        if (!mounted) return;
        setState(() {
          _error = f.toString();
          _loading = false;
        });
      },
    );
  }

  Future<bool?> _terminalConfirm({
    required String title,
    required String body,
    String cancelLabel = 'CANCEL',
    String confirmLabel = 'CONFIRM',
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        final t = Theme.of(ctx);
        final scheme = t.colorScheme;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 24,
          ),
          child: DesktopEscScope(
            child: TerminalContainer(
              showBorder: true,
              showGlow: false,
              borderColor: destructive ? scheme.error : scheme.primary,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: _RoomInfoStyles.sectionHeader(t),
                  ),
                  const SizedBox(height: 12),
                  Text(body, style: _RoomInfoStyles.bodyMuted(t)),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: TerminalButton(
                          text: cancelLabel,
                          onPressed: () => Navigator.pop(ctx, false),
                          isPrimary: false,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TerminalButton(
                          text: confirmLabel,
                          onPressed: () => Navigator.pop(ctx, true),
                          isPrimary: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _presentRoomInfoAuxiliary(
    Widget Function(BuildContext sheetContext) builder, {
    bool scrollControlled = true,
  }) async {
    if (!mounted) return;
    if (isDesktopTargetPlatform() && preferDialogOverModalSheet(context)) {
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) {
          final h = MediaQuery.sizeOf(dialogCtx).height * 0.88;
          return Dialog(
            clipBehavior: Clip.antiAlias,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 640, maxHeight: h),
              child: DesktopEscScope(child: builder(dialogCtx)),
            ),
          );
        },
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: scrollControlled,
      backgroundColor: Colors.transparent,
      builder: builder,
    );
  }

  Future<void> _kick(RoomMemberRow m) async {
    final ok = await _terminalConfirm(
      title: 'remove_node',
      body: 'Kick ${m.displayName} from this room?',
      confirmLabel: 'KICK',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final r = await _service.kickRoomMember(
      roomId: widget.roomId,
      userId: m.userId,
    );
    r.fold(
      (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${m.displayName} was removed')));
        _loadDetails();
      },
      (f) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kick failed: $f'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
    );
  }

  Future<void> _setPower(RoomMemberRow m, int level, String label) async {
    final r = await _service.setRoomMemberPowerLevel(
      roomId: widget.roomId,
      userId: m.userId,
      powerLevel: level,
    );
    r.fold(
      (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$label — ${m.displayName}')));
        _loadDetails();
      },
      (f) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $f'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
    );
  }

  Future<void> _confirmLeave({
    required bool forget,
    BuildContext? sheetContext,
  }) async {
    final ok = await _terminalConfirm(
      title: forget ? 'leave_purge' : 'leave_session',
      body: forget
          ? 'You will leave this room and it will be removed from your room list.'
          : 'You will leave this room. It may stay in your list until forgotten.',
      confirmLabel: forget ? 'LEAVE & PURGE' : 'LEAVE',
      destructive: forget,
    );
    if (ok != true || !mounted) return;

    final Result<String> r = forget
        ? await _service.leaveAndForgetRoom(widget.roomId)
        : await _service.leaveRoomOnly(widget.roomId);

    r.fold(
      (_) {
        if (sheetContext != null) {
          Navigator.of(sheetContext).pop();
        }
        Navigator.of(context).pop(const RoomInfoNavResult(leftRoom: true));
      },
      (f) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Leave failed: $f'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
    );
  }

  String _roleLabel(RoomMemberRoleDto r) {
    switch (r) {
      case RoomMemberRoleDto.creator:
        return 'Creator';
      case RoomMemberRoleDto.administrator:
        return 'Admin';
      case RoomMemberRoleDto.moderator:
        return 'Moderator';
      case RoomMemberRoleDto.user:
        return 'Member';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = (_details?.displayName ?? widget.initialTitle ?? 'ROOM')
        .toUpperCase();

    final screen = TerminalScreen(
      title: title,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadDetails,
          tooltip: 'Refresh',
        ),
      ],
      child: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: theme.colorScheme.primary,
                strokeWidth: 2,
              ),
            )
          : _error != null
          ? Center(
              child: Padding(
                padding: _RoomInfoStyles.listPadding,
                child: Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _buildInfoTab(theme),
    );
    if (isDesktopTargetPlatform()) {
      return DesktopEscScope(child: screen);
    }
    return screen;
  }

  Widget _buildInfoTab(ThemeData theme) {
    final d = _details!;
    final scheme = theme.colorScheme;
    return ListView(
      padding: _RoomInfoStyles.listPadding,
      children: [
        Text('ROOM', style: _RoomInfoStyles.sectionHeader(theme)),
        const SizedBox(height: 8),
        Text('> ROOM DETAILS', style: _RoomInfoStyles.prompt(theme)),
        const SizedBox(height: 6),
        SelectableText(
          d.roomId,
          style: _RoomInfoStyles.captionMuted(theme).copyWith(fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          'Signed in as ${d.currentUserId}',
          style: _RoomInfoStyles.captionMuted(theme).copyWith(fontSize: 11),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 16),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            border: Border(left: BorderSide(color: scheme.primary, width: 3)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: _RoomInfoStyles.blockPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DISPLAY NAME', style: _RoomInfoStyles.prompt(theme)),
                const SizedBox(height: 8),
                SelectableText(
                  d.displayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (d.topic.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _RoomInfoStyles.sectionDivider(theme),
                  const SizedBox(height: 12),
                  Text('TOPIC', style: _RoomInfoStyles.prompt(theme)),
                  const SizedBox(height: 6),
                  SelectableText(
                    d.topic,
                    style: _RoomInfoStyles.bodyMuted(theme),
                  ),
                ],
                const SizedBox(height: 14),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.55),
                    ),
                    color: scheme.primary.withValues(alpha: 0.1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Text(
                      'Encrypted: ${d.isEncrypted ? "yes" : "no"} · '
                      'Members: ${d.memberCount} · '
                      '${d.isDirect ? "Direct" : "Group"}',
                      style: _RoomInfoStyles.captionMuted(theme).copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('MORE', style: _RoomInfoStyles.sectionHeader(theme)),
        _RoomInfoStyles.sectionDivider(theme),
        const SizedBox(height: 8),
        _roomLinkRow(
          theme,
          label: 'Media',
          icon: Icons.perm_media_outlined,
          onTap: () => _showMediaBottomSheet(theme),
        ),
        _roomLinkRow(
          theme,
          label: 'Links',
          icon: Icons.link_outlined,
          onTap: () => _showLinksBottomSheet(theme),
        ),
        if (!d.isDirect)
          _roomLinkRow(
            theme,
            label: 'Polls',
            icon: Icons.poll_outlined,
            onTap: () => _showPollsBottomSheet(theme),
          ),
        _roomLinkRow(
          theme,
          label: 'Actions',
          icon: Icons.bolt_outlined,
          onTap: _showActionsBottomSheet,
        ),
        if (!d.isDirect && d.members.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('MEMBERS', style: _RoomInfoStyles.sectionHeader(theme)),
          _RoomInfoStyles.sectionDivider(theme),
          const SizedBox(height: 8),
          ...d.members.map((m) => _memberTile(theme, d, m)),
        ],
        if (!d.isDirect && d.members.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Member list will appear after sync.',
              style: _RoomInfoStyles.captionMuted(theme),
            ),
          ),
      ],
    );
  }

  Widget _roomLinkRow(
    ThemeData theme, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: scheme.primary, width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(icon, color: scheme.primary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.primary, size: 22),
          ],
        ),
      ),
    );
  }

  void _showMediaBottomSheet(ThemeData theme) {
    unawaited(
      _presentRoomInfoAuxiliary(
        (sheetContext) => _RoomInfoMediaBottomSheet(
          roomId: widget.roomId,
          service: _service,
          theme: theme,
          rootContext: context,
        ),
      ),
    );
  }

  void _showLinksBottomSheet(ThemeData theme) {
    unawaited(
      _presentRoomInfoAuxiliary(
        (sheetContext) => _RoomInfoLinksBottomSheet(
          roomId: widget.roomId,
          service: _service,
          theme: theme,
          rootContext: context,
        ),
      ),
    );
  }

  void _showPollsBottomSheet(ThemeData theme) {
    unawaited(
      _presentRoomInfoAuxiliary(
        (sheetContext) => _RoomInfoPollsBottomSheet(
          roomId: widget.roomId,
          service: _service,
          theme: theme,
          rootContext: context,
        ),
      ),
    );
  }

  void _showActionsBottomSheet() {
    unawaited(
      _presentRoomInfoAuxiliary((sheetContext) {
        final theme = Theme.of(sheetContext);
        final scheme = theme.colorScheme;
        final r = MediaQuery.of(sheetContext).padding;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + r.bottom),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.55)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: scheme.outline.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'LEAVE ROOM',
                    style: _RoomInfoStyles.sectionHeader(theme),
                  ),
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: scheme.error.withValues(alpha: 0.65),
                      ),
                      color: scheme.error.withValues(alpha: 0.08),
                    ),
                    child: Padding(
                      padding: _RoomInfoStyles.blockPadding,
                      child: Text(
                        'Leave disconnects you on the homeserver.\n'
                        'Remove from list also forgets the room locally.',
                        style: _RoomInfoStyles.captionMuted(
                          theme,
                        ).copyWith(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TerminalButton(
                    text: 'LEAVE ROOM',
                    onPressed: () => _confirmLeave(
                      forget: false,
                      sheetContext: sheetContext,
                    ),
                    icon: Icons.logout,
                    isPrimary: false,
                  ),
                  const SizedBox(height: 12),
                  TerminalButton(
                    text: 'LEAVE & REMOVE FROM LIST',
                    onPressed: () =>
                        _confirmLeave(forget: true, sheetContext: sheetContext),
                    icon: Icons.delete_forever_outlined,
                    isPrimary: false,
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _memberTile(ThemeData theme, RoomDetails d, RoomMemberRow m) {
    final admin = d.currentUserIsAdmin;
    final showMenu = !m.isSelf && (admin || m.currentUserCanKick);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: scheme.primary, width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.person, color: scheme.primary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.displayName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (m.isSelf)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.85),
                          ),
                          color: scheme.primary.withValues(alpha: 0.15),
                        ),
                        child: Text(
                          'YOU',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            fontSize: 9,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  m.userIdDisplay,
                  style: _RoomInfoStyles.captionMuted(
                    theme,
                  ).copyWith(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_roleLabel(m.role)} · power ${m.powerLevel}',
                  style: _RoomInfoStyles.captionMuted(theme),
                ),
              ],
            ),
          ),
          if (showMenu)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: scheme.primary),
              onSelected: (value) async {
                switch (value) {
                  case 'kick':
                    if (m.currentUserCanKick) await _kick(m);
                    break;
                  case 'mod':
                    if (admin) await _setPower(m, 50, 'Set moderator');
                    break;
                  case 'admin':
                    if (admin) await _setPower(m, 100, 'Set admin');
                    break;
                  case 'user':
                    if (admin) await _setPower(m, 0, 'Set member');
                    break;
                }
              },
              itemBuilder: (ctx) => [
                if (m.currentUserCanKick)
                  const PopupMenuItem(
                    value: 'kick',
                    child: Text('Kick / remove'),
                  ),
                if (admin) ...[
                  const PopupMenuItem(
                    value: 'mod',
                    child: Text('Make moderator'),
                  ),
                  const PopupMenuItem(
                    value: 'admin',
                    child: Text('Make admin'),
                  ),
                  const PopupMenuItem(
                    value: 'user',
                    child: Text('Make member'),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _RoomInfoMediaBottomSheet extends StatefulWidget {
  const _RoomInfoMediaBottomSheet({
    required this.roomId,
    required this.service,
    required this.theme,
    required this.rootContext,
  });

  final String roomId;
  final ConversationService service;
  final ThemeData theme;
  final BuildContext rootContext;

  @override
  State<_RoomInfoMediaBottomSheet> createState() =>
      _RoomInfoMediaBottomSheetState();
}

class _RoomInfoMediaBottomSheetState extends State<_RoomInfoMediaBottomSheet> {
  RoomFileFilter _fileFilter = RoomFileFilter.all;
  List<RoomFileItem> _files = [];
  bool _filesLoading = true;
  String? _filesError;
  final ScrollController _listScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    TimelineLocalHiddenStore.revision.addListener(_onLocalHiddenChanged);
    _loadFiles();
  }

  @override
  void dispose() {
    TimelineLocalHiddenStore.revision.removeListener(_onLocalHiddenChanged);
    _listScrollController.dispose();
    super.dispose();
  }

  void _onLocalHiddenChanged() {
    if (!mounted) return;
    _loadFiles(showLoadingIndicator: false);
  }

  Future<void> _loadFiles({bool showLoadingIndicator = true}) async {
    if (showLoadingIndicator) {
      setState(() {
        _filesLoading = true;
        _filesError = null;
      });
    }
    final r = await widget.service.listRoomFiles(
      roomId: widget.roomId,
      filter: _fileFilter,
    );
    if (!mounted) return;
    r.fold(
      (list) => setState(() {
        _files = list;
        _filesLoading = false;
        _filesError = null;
      }),
      (f) => setState(() {
        if (showLoadingIndicator) {
          _filesError = f.toString();
        }
        _filesLoading = false;
      }),
    );
  }

  String _kindLabel(RoomMessageKind k) {
    switch (k) {
      case RoomMessageKind.text:
        return 'Text';
      case RoomMessageKind.image:
        return 'Image';
      case RoomMessageKind.file:
        return 'File';
      case RoomMessageKind.video:
        return 'Video';
      case RoomMessageKind.audio:
        return 'Audio';
      case RoomMessageKind.poll:
        return 'Poll';
      case RoomMessageKind.other:
        return 'Other';
    }
  }

  DateTime? _fileTime(RoomFileItem f) {
    try {
      final t = f.timestamp;
      // ignore: dead_code, unnecessary_type_check — BigInt on web, int on IO.
      final int ms = t is BigInt ? t.toInt() : t as int;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _fileSizeLabel(RoomFileItem f) {
    try {
      final b = f.sizeBytes;
      if (b <= BigInt.zero) return '—';
      var v = b.toDouble();
      if (!v.isFinite || v <= 0) {
        return '${b.toString()} B';
      }
      const units = ['B', 'KB', 'MB', 'GB'];
      var u = 0;
      while (v >= 1024 && u < units.length - 1) {
        v /= 1024;
        u++;
        if (!v.isFinite) {
          return '${b.toString()} B';
        }
      }
      if (u == 0) return '${b.toString()} B';
      final decimals = v >= 100 || (v - v.round()).abs() < 1e-6 ? 0 : 1;
      if (!v.isFinite) return '${b.toString()} B';
      return '${v.toStringAsFixed(decimals)} ${units[u]}';
    } catch (_) {
      return '—';
    }
  }

  String _fileListTimeLabel(DateTime? t) {
    if (t == null) return '?';
    final s = t.toLocal().toString();
    if (s.length <= 19) return s;
    return s.substring(0, 19);
  }

  Future<Uint8List?> _fetchRoomMedia(
    String eventId, {
    bool thumbnail = true,
  }) async {
    if (eventId.isEmpty) return null;
    final r = await widget.service.fetchRoomMessageMedia(
      roomId: widget.roomId,
      eventId: eventId,
      thumbnail: thumbnail,
    );
    return r.fold((b) => b, (_) => null);
  }

  Future<void> _previewRoomFile(RoomFileItem f) async {
    if (f.eventId.isEmpty || !mounted) return;
    final label = f.caption.trim().isEmpty ? 'attachment' : f.caption.trim();
    await AttachmentViewer.open(
      context,
      loadFullBytes: () => _fetchRoomMedia(f.eventId, thumbnail: false),
      filename: label,
      roomMsgKind: f.kind,
    );
  }

  void _jumpToMessageInChat(RoomFileItem f) {
    if (f.eventId.isEmpty) return;
    final root = widget.rootContext;
    if (!root.mounted) return;
    // Pop the modal sheet using the room route's navigator (top route = sheet),
    // then pop room info on the next frame so we never stack two pops in one
    // build/layout pass (avoids parent-data / scroll glitches).
    Navigator.of(root).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!root.mounted) return;
      Navigator.of(root).pop(RoomInfoNavResult(focusEventId: f.eventId));
    });
  }

  String _captionExtLower(RoomFileItem f) {
    final base = p.basename(f.caption.trim());
    final dot = base.lastIndexOf('.');
    if (dot < 0 || dot >= base.length - 1) return '';
    return base.substring(dot + 1).toLowerCase();
  }

  static const _fileFilterIcons = (
    all: Icons.grid_view_rounded,
    received: Icons.south_west_rounded,
    sent: Icons.north_east_rounded,
  );

  Widget _fileFilterDivider(Color c) {
    return Container(width: 1, color: c);
  }

  Widget _fileFilterSegment({
    required RoomFileFilter filter,
    required String label,
    required String tooltip,
    required IconData icon,
  }) {
    final t = widget.theme;
    final scheme = t.colorScheme;
    final selected = _fileFilter == filter;
    final dim = scheme.onSurface.withValues(alpha: 0.5);
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (_fileFilter == filter) return;
              setState(() => _fileFilter = filter);
              _loadFiles();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.12)
                    : scheme.surface.withValues(alpha: 0.2),
                border: Border(
                  bottom: BorderSide(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: selected ? scheme.primary : dim),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: t.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: selected ? scheme.primary : dim,
                      ),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const double _kFileFilterBarHeight = 72;

  Widget _buildFileFilterBar() {
    final scheme = widget.theme.colorScheme;
    final edge = scheme.primary.withValues(alpha: 0.55);
    final div = scheme.outline.withValues(alpha: 0.35);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: edge, width: 1),
        color: scheme.surfaceContainerHighest,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: _kFileFilterBarHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _fileFilterSegment(
                filter: RoomFileFilter.all,
                label: 'ALL',
                tooltip: 'All attachments',
                icon: _fileFilterIcons.all,
              ),
              _fileFilterDivider(div),
              _fileFilterSegment(
                filter: RoomFileFilter.received,
                label: 'RECEIVED',
                tooltip: 'Received from others',
                icon: _fileFilterIcons.received,
              ),
              _fileFilterDivider(div),
              _fileFilterSegment(
                filter: RoomFileFilter.sent,
                label: 'SENT',
                tooltip: 'Sent by you',
                icon: _fileFilterIcons.sent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilesList() {
    final theme = widget.theme;
    final scheme = theme.colorScheme;
    if (_filesLoading) {
      return Center(
        child: CircularProgressIndicator(color: scheme.primary, strokeWidth: 2),
      );
    }
    if (_filesError != null) {
      return Center(
        child: Padding(
          padding: _RoomInfoStyles.listPadding,
          child: Text(
            _filesError!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.error,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_files.isEmpty) {
      return Center(
        child: Padding(
          padding: _RoomInfoStyles.listPadding,
          child: Text(
            '∅ no blobs in local event cache for this shard.\n'
            'sync room; ciphertext resolves after decrypt.',
            style: _RoomInfoStyles.captionMuted(theme).copyWith(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _listScrollController,
      padding: _RoomInfoStyles.listPadding.copyWith(top: 0, bottom: 24),
      itemCount: _files.length,
      itemBuilder: (ctx, i) {
        final f = _files[i];
        final t = _fileTime(f);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _RoomFileThumbnail(
                    item: f,
                    theme: theme,
                    loadThumbnail: _fetchRoomMedia,
                    extLower: _captionExtLower(f),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _roomFileIcon(f.kind),
                              size: 15,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                f.caption.isEmpty ? '⟨untitled⟩' : f.caption,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                '${_kindLabel(f.kind)} · '
                                '${f.isOutgoing ? "Sent" : "Received"} · '
                                '${_fileListTimeLabel(t)} · '
                                '${_fileSizeLabel(f)}',
                                style: _RoomInfoStyles.captionMuted(
                                  theme,
                                ).copyWith(fontSize: 10),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (f.eventId.isNotEmpty) ...[
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                padding: EdgeInsets.zero,
                                tooltip: 'Preview',
                                onPressed: () => _previewRoomFile(f),
                                icon: Icon(
                                  Icons.visibility_outlined,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                padding: EdgeInsets.zero,
                                tooltip: 'Jump to message',
                                onPressed: () => _jumpToMessageInChat(f),
                                icon: Icon(
                                  Icons.chat_bubble_outline,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final scheme = theme.colorScheme;
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.9;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: sheetHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outline.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        'MEDIA',
                        style: _RoomInfoStyles.sectionHeader(theme),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: scheme.primary,
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: _RoomInfoStyles.listPadding.copyWith(
                  top: 0,
                  bottom: 10,
                ),
                child: _buildFileFilterBar(),
              ),
              Expanded(child: _buildFilesList()),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomInfoLinksBottomSheet extends StatefulWidget {
  const _RoomInfoLinksBottomSheet({
    required this.roomId,
    required this.service,
    required this.theme,
    required this.rootContext,
  });

  final String roomId;
  final ConversationService service;
  final ThemeData theme;
  final BuildContext rootContext;

  @override
  State<_RoomInfoLinksBottomSheet> createState() =>
      _RoomInfoLinksBottomSheetState();
}

class _RoomInfoLinksBottomSheetState extends State<_RoomInfoLinksBottomSheet> {
  RoomFileFilter _filter = RoomFileFilter.all;
  List<RoomLinkItem> _links = [];
  bool _loading = true;
  String? _error;
  final ScrollController _scroll = ScrollController();

  static const _filterIcons = (
    all: Icons.grid_view_rounded,
    received: Icons.south_west_rounded,
    sent: Icons.north_east_rounded,
  );

  @override
  void initState() {
    super.initState();
    TimelineLocalHiddenStore.revision.addListener(_onLocalHiddenChanged);
    _load();
  }

  @override
  void dispose() {
    TimelineLocalHiddenStore.revision.removeListener(_onLocalHiddenChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onLocalHiddenChanged() {
    if (!mounted) return;
    _load(showLoadingIndicator: false);
  }

  Future<void> _load({bool showLoadingIndicator = true}) async {
    if (showLoadingIndicator) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final r = await widget.service.listRoomLinks(
      roomId: widget.roomId,
      filter: _filter,
    );
    if (!mounted) return;
    r.fold(
      (list) => setState(() {
        _links = list;
        _loading = false;
        _error = null;
      }),
      (f) => setState(() {
        if (showLoadingIndicator) {
          _error = f.toString();
        }
        _loading = false;
      }),
    );
  }

  DateTime? _linkTime(RoomLinkItem item) {
    try {
      final t = item.timestamp;
      // ignore: dead_code, unnecessary_type_check — BigInt on web, int on IO.
      final int ms = t is BigInt ? t.toInt() : t as int;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _listTimeLabel(DateTime? t) {
    if (t == null) return '?';
    final s = t.toLocal().toString();
    if (s.length <= 19) return s;
    return s.substring(0, 19);
  }

  void _jumpToMessageInChat(RoomLinkItem item) {
    if (item.eventId.isEmpty) return;
    final root = widget.rootContext;
    if (!root.mounted) return;
    Navigator.of(root).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!root.mounted) return;
      Navigator.of(root).pop(RoomInfoNavResult(focusEventId: item.eventId));
    });
  }

  Widget _linksFilterDivider(Color c) {
    return Container(width: 1, color: c);
  }

  Widget _linksFilterSegment({
    required RoomFileFilter filter,
    required String label,
    required String tooltip,
    required IconData icon,
  }) {
    final t = widget.theme;
    final scheme = t.colorScheme;
    final selected = _filter == filter;
    final dim = scheme.onSurface.withValues(alpha: 0.5);
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (_filter == filter) return;
              setState(() => _filter = filter);
              _load();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.12)
                    : scheme.surface.withValues(alpha: 0.2),
                border: Border(
                  bottom: BorderSide(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: selected ? scheme.primary : dim),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: t.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: selected ? scheme.primary : dim,
                      ),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const double _kLinksFilterBarHeight = 72;

  Widget _buildLinksFilterBar() {
    final scheme = widget.theme.colorScheme;
    final edge = scheme.primary.withValues(alpha: 0.55);
    final div = scheme.outline.withValues(alpha: 0.35);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: edge, width: 1),
        color: scheme.surfaceContainerHighest,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: _kLinksFilterBarHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _linksFilterSegment(
                filter: RoomFileFilter.all,
                label: 'ALL',
                tooltip: 'All link messages',
                icon: _filterIcons.all,
              ),
              _linksFilterDivider(div),
              _linksFilterSegment(
                filter: RoomFileFilter.received,
                label: 'RECEIVED',
                tooltip: 'Received from others',
                icon: _filterIcons.received,
              ),
              _linksFilterDivider(div),
              _linksFilterSegment(
                filter: RoomFileFilter.sent,
                label: 'SENT',
                tooltip: 'Sent by you',
                icon: _filterIcons.sent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkListThumb() {
    const size = 40.0;
    final scheme = widget.theme.colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      ),
      child: Icon(Icons.link_rounded, size: 22, color: scheme.primary),
    );
  }

  Widget _buildLinksList() {
    final theme = widget.theme;
    final scheme = theme.colorScheme;
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: scheme.primary, strokeWidth: 2),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: _RoomInfoStyles.listPadding,
          child: Text(
            _error!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.error,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_links.isEmpty) {
      return Center(
        child: Padding(
          padding: _RoomInfoStyles.listPadding,
          child: Text(
            '∅ no link messages in local event cache for this shard.\n'
            'sync room; URLs are indexed from decrypted timeline.',
            style: _RoomInfoStyles.captionMuted(theme).copyWith(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: _RoomInfoStyles.listPadding.copyWith(top: 0, bottom: 24),
      itemCount: _links.length,
      itemBuilder: (ctx, i) {
        final item = _links[i];
        final t = _linkTime(item);
        final accent = scheme.primary;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _linkListThumb(),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.link, size: 15, color: accent),
                                const SizedBox(width: 6),
                                if (item.isLinkMessage)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: accent.withValues(alpha: 0.45),
                                        ),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text(
                                        'PREVIEW',
                                        style:
                                            _RoomInfoStyles.captionMuted(
                                              theme,
                                            ).copyWith(
                                              fontSize: 8,
                                              color: accent,
                                              letterSpacing: 0.6,
                                            ),
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: SelectableLinkify(
                                    text: item.body.isEmpty
                                        ? '⟨empty⟩'
                                        : item.body,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                    linkStyle: theme.textTheme.bodyMedium
                                        ?.copyWith(
                                          color: accent,
                                          decoration: TextDecoration.underline,
                                          decorationColor: accent,
                                        ),
                                    onOpen: (link) =>
                                        openMatrixUrl(context, link.url),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item.isOutgoing ? "Sent" : "Received"} · '
                              '${_listTimeLabel(t)}',
                              style: _RoomInfoStyles.captionMuted(
                                theme,
                              ).copyWith(fontSize: 10),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (item.eventId.isNotEmpty)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          padding: EdgeInsets.zero,
                          tooltip: 'Jump to message',
                          onPressed: () => _jumpToMessageInChat(item),
                          icon: Icon(
                            Icons.chat_bubble_outline,
                            size: 18,
                            color: accent,
                          ),
                        ),
                    ],
                  ),
                  if (matrixLinkPreviewsJsonHasData(item.linkPreviewsJson))
                    MatrixLinkPreviewCards(
                      linkPreviewsJson: item.linkPreviewsJson,
                      accentColor: accent,
                      compact: false,
                      onOpenUrl: (u) => openMatrixUrl(context, u),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final scheme = theme.colorScheme;
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.9;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: sheetHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outline.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        'LINKS',
                        style: _RoomInfoStyles.sectionHeader(theme),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: scheme.primary,
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: _RoomInfoStyles.listPadding.copyWith(
                  top: 0,
                  bottom: 10,
                ),
                child: _buildLinksFilterBar(),
              ),
              Expanded(child: _buildLinksList()),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isRoomInfoRasterBytes(Uint8List data) {
  if (data.length < 12) return false;
  if (data.length >= 3 &&
      data[0] == 0xFF &&
      data[1] == 0xD8 &&
      data[2] == 0xFF) {
    return true;
  }
  if (data.length >= 8 &&
      data[0] == 0x89 &&
      data[1] == 0x50 &&
      data[2] == 0x4E &&
      data[3] == 0x47 &&
      data[4] == 0x0D &&
      data[5] == 0x0A &&
      data[6] == 0x1A &&
      data[7] == 0x0A) {
    return true;
  }
  if (data.length >= 6 &&
      data[0] == 0x47 &&
      data[1] == 0x49 &&
      data[2] == 0x46) {
    final g = String.fromCharCodes(data.sublist(0, 6));
    if (g == 'GIF87a' || g == 'GIF89a') return true;
  }
  if (data.length >= 12 &&
      data[0] == 0x52 &&
      data[1] == 0x49 &&
      data[2] == 0x46 &&
      data[3] == 0x46 &&
      data[8] == 0x57 &&
      data[9] == 0x45 &&
      data[10] == 0x42 &&
      data[11] == 0x50) {
    return true;
  }
  if (data.length >= 2 && data[0] == 0x42 && data[1] == 0x4D) return true;
  return false;
}

class _RoomFileThumbnail extends StatefulWidget {
  const _RoomFileThumbnail({
    required this.item,
    required this.theme,
    required this.loadThumbnail,
    required this.extLower,
  });

  final RoomFileItem item;
  final ThemeData theme;
  final Future<Uint8List?> Function(String eventId, {bool thumbnail})
  loadThumbnail;
  final String extLower;

  @override
  State<_RoomFileThumbnail> createState() => _RoomFileThumbnailState();
}

class _RoomFileThumbnailState extends State<_RoomFileThumbnail> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_RoomFileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.eventId != widget.item.eventId ||
        oldWidget.item.kind != widget.item.kind) {
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.item.eventId;
    final kind = widget.item.kind;
    if (id.isEmpty || kind == RoomMessageKind.audio) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final useThumb =
        kind == RoomMessageKind.image ||
        kind == RoomMessageKind.video ||
        kind == RoomMessageKind.file;
    try {
      var b = await widget.loadThumbnail(id, thumbnail: useThumb);
      if (b != null && b.isNotEmpty && useThumb && !_isRoomInfoRasterBytes(b)) {
        b = null;
      }
      if (!mounted) return;
      setState(() {
        _bytes = b;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bytes = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.theme.colorScheme;
    const size = 40.0;
    const iconSize = 20.0;
    final dim = scheme.onSurface.withValues(alpha: 0.55);
    if (widget.item.eventId.isEmpty) {
      return _thumbShell(
        size,
        scheme,
        Icon(_roomFileIcon(widget.item.kind), size: iconSize, color: dim),
      );
    }
    if (widget.item.kind == RoomMessageKind.audio) {
      return _thumbShell(
        size,
        scheme,
        Icon(Icons.audiotrack, size: iconSize, color: scheme.primary),
      );
    }
    if (_loading) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
        ),
      );
    }
    if (_bytes != null && _bytes!.isNotEmpty) {
      return _thumbShell(
        size,
        scheme,
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Image.memory(
            _bytes!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => Icon(
              _roomFileIcon(widget.item.kind),
              size: iconSize,
              color: dim,
            ),
          ),
        ),
      );
    }
    return _thumbShell(
      size,
      scheme,
      Icon(_roomFileIcon(widget.item.kind), size: iconSize, color: dim),
    );
  }

  Widget _thumbShell(double size, ColorScheme scheme, Widget child) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      ),
      child: child,
    );
  }
}

class _RoomInfoPollsBottomSheet extends StatefulWidget {
  const _RoomInfoPollsBottomSheet({
    required this.roomId,
    required this.service,
    required this.theme,
    required this.rootContext,
  });

  final String roomId;
  final ConversationService service;
  final ThemeData theme;
  final BuildContext rootContext;

  @override
  State<_RoomInfoPollsBottomSheet> createState() =>
      _RoomInfoPollsBottomSheetState();
}

class _RoomInfoPollsBottomSheetState extends State<_RoomInfoPollsBottomSheet> {
  RoomFileFilter _filter = RoomFileFilter.all;
  List<RoomPollItem> _polls = [];
  bool _loading = true;
  String? _error;
  final ScrollController _scroll = ScrollController();

  static const _filterIcons = (
    all: Icons.grid_view_rounded,
    received: Icons.south_west_rounded,
    sent: Icons.north_east_rounded,
  );

  static const double _kPollsFilterBarHeight = 72;

  @override
  void initState() {
    super.initState();
    TimelineLocalHiddenStore.revision.addListener(_onLocalHiddenChanged);
    _load();
  }

  @override
  void dispose() {
    TimelineLocalHiddenStore.revision.removeListener(_onLocalHiddenChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onLocalHiddenChanged() {
    if (!mounted) return;
    _load(showLoadingIndicator: false);
  }

  Future<void> _load({bool showLoadingIndicator = true}) async {
    if (showLoadingIndicator) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final r = await widget.service.listRoomPolls(
      roomId: widget.roomId,
      filter: _filter,
    );
    if (!mounted) return;
    r.fold(
      (list) => setState(() {
        _polls = list;
        _loading = false;
        _error = null;
      }),
      (f) => setState(() {
        if (showLoadingIndicator) {
          _error = f.toString();
        }
        _loading = false;
      }),
    );
  }

  DateTime? _pollTime(RoomPollItem item) {
    try {
      final t = item.timestamp;
      // ignore: dead_code, unnecessary_type_check — BigInt on web, int on IO.
      final int ms = t is BigInt ? t.toInt() : t as int;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _listTimeLabel(DateTime? t) {
    if (t == null) return '?';
    final s = t.toLocal().toString();
    if (s.length <= 19) return s;
    return s.substring(0, 19);
  }

  void _jumpToPollInChat(RoomPollItem item) {
    if (item.eventId.isEmpty) return;
    final root = widget.rootContext;
    if (!root.mounted) return;
    Navigator.of(root).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!root.mounted) return;
      Navigator.of(root).pop(RoomInfoNavResult(focusEventId: item.eventId));
    });
  }

  Widget _pollsFilterDivider(Color c) {
    return Container(width: 1, color: c);
  }

  Widget _pollsFilterSegment({
    required RoomFileFilter filter,
    required String label,
    required String tooltip,
    required IconData icon,
  }) {
    final t = widget.theme;
    final scheme = t.colorScheme;
    final selected = _filter == filter;
    final dim = scheme.onSurface.withValues(alpha: 0.5);
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (_filter == filter) return;
              setState(() => _filter = filter);
              _load();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.12)
                    : scheme.surface.withValues(alpha: 0.2),
                border: Border(
                  bottom: BorderSide(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: selected ? scheme.primary : dim),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: t.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: selected ? scheme.primary : dim,
                      ),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPollsFilterBar() {
    final scheme = widget.theme.colorScheme;
    final edge = scheme.primary.withValues(alpha: 0.55);
    final div = scheme.outline.withValues(alpha: 0.35);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: edge, width: 1),
        color: scheme.surfaceContainerHighest,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: _kPollsFilterBarHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _pollsFilterSegment(
                filter: RoomFileFilter.all,
                label: 'ALL',
                tooltip: 'All polls',
                icon: _filterIcons.all,
              ),
              _pollsFilterDivider(div),
              _pollsFilterSegment(
                filter: RoomFileFilter.received,
                label: 'RECEIVED',
                tooltip: 'Received from others',
                icon: _filterIcons.received,
              ),
              _pollsFilterDivider(div),
              _pollsFilterSegment(
                filter: RoomFileFilter.sent,
                label: 'SENT',
                tooltip: 'Sent by you',
                icon: _filterIcons.sent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pollListThumb() {
    const size = 40.0;
    final scheme = widget.theme.colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      ),
      child: Icon(Icons.poll_rounded, size: 22, color: scheme.primary),
    );
  }

  Widget _buildPollsList() {
    final theme = widget.theme;
    final scheme = theme.colorScheme;
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: scheme.primary, strokeWidth: 2),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: _RoomInfoStyles.listPadding,
          child: Text(
            _error!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.error,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_polls.isEmpty) {
      return Center(
        child: Padding(
          padding: _RoomInfoStyles.listPadding,
          child: Text(
            '∅ no poll events in local event cache for this shard.\n'
            'sync room; polls are indexed from MSC3381 poll.start.',
            style: _RoomInfoStyles.captionMuted(theme).copyWith(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: _RoomInfoStyles.listPadding.copyWith(top: 0, bottom: 24),
      itemCount: _polls.length,
      itemBuilder: (ctx, i) {
        final p = _polls[i];
        final t = _pollTime(p);
        final accent = scheme.primary;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _pollListThumb(),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.how_to_vote_outlined,
                                  size: 15,
                                  color: accent,
                                ),
                                const SizedBox(width: 6),
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: accent.withValues(alpha: 0.45),
                                      ),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: Text(
                                      'POLL',
                                      style: _RoomInfoStyles.captionMuted(theme)
                                          .copyWith(
                                            fontSize: 8,
                                            color: accent,
                                            letterSpacing: 0.6,
                                          ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    p.question.isNotEmpty
                                        ? p.question
                                        : '⟨poll⟩',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${p.isOutgoing ? "Sent" : "Received"} · '
                              '${_listTimeLabel(t)}',
                              style: _RoomInfoStyles.captionMuted(
                                theme,
                              ).copyWith(fontSize: 10),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (p.eventId.isNotEmpty)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          padding: EdgeInsets.zero,
                          tooltip: 'Jump to message',
                          onPressed: () => _jumpToPollInChat(p),
                          icon: Icon(
                            Icons.chat_bubble_outline,
                            size: 18,
                            color: accent,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final scheme = theme.colorScheme;
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.9;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: sheetHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outline.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        'POLLS',
                        style: _RoomInfoStyles.sectionHeader(theme),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: scheme.primary,
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: _RoomInfoStyles.listPadding.copyWith(
                  top: 0,
                  bottom: 10,
                ),
                child: _buildPollsFilterBar(),
              ),
              Expanded(child: _buildPollsList()),
            ],
          ),
        ),
      ),
    );
  }
}
