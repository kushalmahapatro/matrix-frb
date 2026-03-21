import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/conversation/domain/services/conversation_service.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix/src/features/conversation/presentation/widgets/attachment_viewer.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix_sdk/matrix_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart';

/// Pop result from [RoomInfoScreen]: leaving the room, or focusing a timeline event.
class RoomInfoNavResult {
  const RoomInfoNavResult({
    this.leftRoom = false,
    this.focusEventId,
  });

  final bool leftRoom;
  final String? focusEventId;
}

/// Room info UI: denser Matrix terminal readout (greens + teal accent).
abstract final class _RoomInfoTerminal {
  static const EdgeInsets screenPadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 18);
  static const EdgeInsets blockPadding = EdgeInsets.all(18);

  static TextStyle promptLabel(BuildContext context) =>
      MatrixTheme.labelStyle.copyWith(
        color: MatrixTheme.matrixAccent,
        fontSize: 11,
        letterSpacing: 2,
      );

  static TextStyle sectionTitle(BuildContext context) =>
      MatrixTheme.labelStyle.copyWith(
        color: MatrixTheme.matrixLightGreen,
        fontSize: 12,
        letterSpacing: 3,
      );

  static TextStyle bodyDim(BuildContext context) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
        color: MatrixTheme.matrixGreen.withValues(alpha: 0.85),
        fontFamily: MatrixTheme.fontFamily,
        height: 1.45,
      );

  static TextStyle metaLine(BuildContext context) =>
      MatrixTheme.captionStyle.copyWith(
        color: MatrixTheme.matrixDarkGreen,
        fontSize: 11,
        height: 1.35,
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
    case RoomMessageKind.other:
      return Icons.attach_file_outlined;
  }
}

/// Full-screen room details: manifest + members; media and actions in bottom sheets.
class RoomInfoScreen extends StatefulWidget {
  const RoomInfoScreen({
    super.key,
    required this.roomId,
    this.initialTitle,
  });

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

  Future<void> _kick(RoomMemberRow m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member'),
        content: Text('Kick ${m.displayName} from this room?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kick'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await _service.kickRoomMember(
      roomId: widget.roomId,
      userId: m.userId,
    );
    r.fold(
      (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${m.displayName} was removed')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label — ${m.displayName}')),
        );
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(forget ? 'Leave and remove' : 'Leave room'),
        content: Text(
          forget
              ? 'You will leave this room and it will be removed from your room list.'
              : 'You will leave this room. It may stay in your list until forgotten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(forget ? 'Leave & remove' : 'Leave'),
          ),
        ],
      ),
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

    return TerminalScreen(
      title: title,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          color: MatrixTheme.matrixGreen,
          onPressed: _loadDetails,
          tooltip: 'Refresh',
        ),
      ],
      child: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: MatrixTheme.matrixAccent,
                strokeWidth: 2,
              ),
            )
          : _error != null
          ? Center(
              child: Padding(
                padding: _RoomInfoTerminal.screenPadding,
                child: Text(
                  _error!,
                  style: MatrixTheme.errorStyle.copyWith(
                    fontSize: 14,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _buildInfoTab(theme),
    );
  }

  Widget _buildInfoTab(ThemeData theme) {
    final d = _details!;
    return ListView(
      padding: _RoomInfoTerminal.screenPadding,
      children: [
        Text(
          '> ROOM_MANIFEST // SECURE_CHANNEL',
          style: _RoomInfoTerminal.promptLabel(context),
        ),
        const SizedBox(height: 10),
        TerminalContainer(
          padding: _RoomInfoTerminal.blockPadding,
          showGlow: true,
          borderColor: MatrixTheme.matrixAccent.withValues(alpha: 0.65),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '[ DISPLAY_NAME ]',
                style: _RoomInfoTerminal.promptLabel(context),
              ),
              const SizedBox(height: 10),
              SelectableText(
                d.displayName,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: MatrixTheme.matrixLightGreen,
                  fontFamily: MatrixTheme.fontFamily,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              if (d.topic.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  '[ TOPIC ]',
                  style: _RoomInfoTerminal.promptLabel(context),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  d.topic,
                  style: _RoomInfoTerminal.bodyDim(context),
                ),
              ],
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: MatrixTheme.statusDecoration,
                child: Text(
                  'encrypted: ${d.isEncrypted ? "true" : "false"}  │  '
                  'nodes: ${d.memberCount}  │  '
                  'topology: ${d.isDirect ? "1:1" : "mesh"}',
                  style: _RoomInfoTerminal.metaLine(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('// ROOM', style: _RoomInfoTerminal.sectionTitle(context)),
        const SizedBox(height: 10),
        _roomLinkRow(
          theme,
          label: 'Media',
          icon: Icons.perm_media_outlined,
          onTap: () => _showMediaBottomSheet(theme),
        ),
        const SizedBox(height: 8),
        _roomLinkRow(
          theme,
          label: 'Actions',
          icon: Icons.bolt_outlined,
          onTap: _showActionsBottomSheet,
        ),
        if (!d.isDirect && d.members.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('// MEMBER_REGISTRY', style: _RoomInfoTerminal.sectionTitle(context)),
          const SizedBox(height: 12),
          ...d.members.map((m) => _memberTile(theme, d, m)),
        ],
        if (!d.isDirect && d.members.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(
              '… member index pending sync',
              style: _RoomInfoTerminal.metaLine(context),
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
    return TerminalContainer(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      borderColor: MatrixTheme.matrixGreen.withValues(alpha: 0.45),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(2),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: MatrixTheme.matrixAccent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: MatrixTheme.matrixLightGreen,
                      fontFamily: MatrixTheme.fontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: MatrixTheme.matrixDarkGreen.withValues(alpha: 0.85),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMediaBottomSheet(ThemeData theme) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _RoomInfoMediaBottomSheet(
          roomId: widget.roomId,
          service: _service,
          theme: theme,
          rootContext: context,
        );
      },
    );
  }

  void _showActionsBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final r = MediaQuery.of(sheetContext).padding;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + r.bottom),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: MatrixTheme.terminalBlack.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: MatrixTheme.matrixGreen.withValues(alpha: 0.4),
              ),
              boxShadow: [
                BoxShadow(
                  color: MatrixTheme.matrixAccent.withValues(alpha: 0.1),
                  blurRadius: 16,
                ),
              ],
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
                        color: MatrixTheme.matrixDarkGreen.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    '> SESSION_CONTROL',
                    style: _RoomInfoTerminal.promptLabel(context),
                  ),
                  const SizedBox(height: 12),
                  TerminalContainer(
                    padding: _RoomInfoTerminal.blockPadding,
                    borderColor: MatrixTheme.warningOrange.withValues(alpha: 0.55),
                    child: Text(
                      'disconnect: leave room on homeserver.\n'
                      'purge: leave + forget → drops local room index.',
                      style: _RoomInfoTerminal.metaLine(context).copyWith(fontSize: 12),
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
                    onPressed: () => _confirmLeave(
                      forget: true,
                      sheetContext: sheetContext,
                    ),
                    icon: Icons.delete_forever_outlined,
                    isPrimary: false,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _memberTile(ThemeData theme, RoomDetails d, RoomMemberRow m) {
    final admin = d.currentUserIsAdmin;
    final showMenu =
        !m.isSelf && (admin || m.currentUserCanKick);
    return TerminalContainer(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderColor: MatrixTheme.matrixGreen.withValues(alpha: 0.45),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 44,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: MatrixTheme.matrixAccent.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.displayName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: MatrixTheme.matrixGreen,
                          fontFamily: MatrixTheme.fontFamily,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (m.isSelf)
                      Text(
                        '⟨local⟩',
                        style: _RoomInfoTerminal.promptLabel(context),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  m.userId,
                  style: _RoomInfoTerminal.metaLine(context).copyWith(
                    color: MatrixTheme.matrixDarkGreen,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'role=${_roleLabel(m.role).toLowerCase()}  pl=${m.powerLevel}',
                  style: _RoomInfoTerminal.metaLine(context),
                ),
              ],
            ),
          ),
          if (showMenu)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: MatrixTheme.matrixGreen.withValues(alpha: 0.8)),
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
                  const PopupMenuItem(value: 'mod', child: Text('Make moderator')),
                  const PopupMenuItem(value: 'admin', child: Text('Make admin')),
                  const PopupMenuItem(value: 'user', child: Text('Make member')),
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
    _loadFiles();
  }

  @override
  void dispose() {
    _listScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _filesLoading = true;
      _filesError = null;
    });
    final r = await widget.service.listRoomFiles(
      roomId: widget.roomId,
      filter: _fileFilter,
    );
    if (!mounted) return;
    r.fold(
      (list) => setState(() {
        _files = list;
        _filesLoading = false;
      }),
      (f) => setState(() {
        _filesError = f.toString();
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
      Navigator.of(root).pop(
        RoomInfoNavResult(focusEventId: f.eventId),
      );
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
    final selected = _fileFilter == filter;
    final dim = MatrixTheme.matrixDarkGreen.withValues(alpha: 0.88);
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
                    ? MatrixTheme.matrixDarkGreen.withValues(alpha: 0.42)
                    : MatrixTheme.terminalBlack.withValues(alpha: 0.25),
                border: Border(
                  bottom: BorderSide(
                    color: selected
                        ? MatrixTheme.matrixAccent
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? MatrixTheme.matrixLightGreen : dim,
                  ),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: MatrixTheme.captionStyle.copyWith(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w500,
                        color: selected ? MatrixTheme.matrixGreen : dim,
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
    final edge = MatrixTheme.matrixGreen.withValues(alpha: 0.42);
    final div = MatrixTheme.matrixGreen.withValues(alpha: 0.22);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: edge, width: 1),
        color: MatrixTheme.terminalBlack.withValues(alpha: 0.78),
        boxShadow: [
          BoxShadow(
            color: MatrixTheme.matrixAccent.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
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
    if (_filesLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: MatrixTheme.matrixAccent,
          strokeWidth: 2,
        ),
      );
    }
    if (_filesError != null) {
      return Center(
        child: Padding(
          padding: _RoomInfoTerminal.screenPadding,
          child: Text(
            _filesError!,
            style: MatrixTheme.errorStyle.copyWith(height: 1.4),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_files.isEmpty) {
      return Center(
        child: Padding(
          padding: _RoomInfoTerminal.screenPadding,
          child: Text(
            '∅ no blobs in local event cache for this shard.\n'
            'sync room; ciphertext resolves after decrypt.',
            style: _RoomInfoTerminal.metaLine(context).copyWith(
              fontSize: 12,
              color: MatrixTheme.matrixDarkGreen,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _listScrollController,
      padding: _RoomInfoTerminal.screenPadding.copyWith(top: 0, bottom: 24),
      itemCount: _files.length,
      itemBuilder: (ctx, i) {
        final f = _files[i];
        final t = _fileTime(f);
        return TerminalContainer(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          showBorder: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _RoomFileThumbnail(
                item: f,
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
                          color: MatrixTheme.matrixAccent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            f.caption.isEmpty ? '⟨untitled⟩' : f.caption,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: MatrixTheme.matrixLightGreen,
                              fontFamily: MatrixTheme.fontFamily,
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
                            style: _RoomInfoTerminal.metaLine(context)
                                .copyWith(fontSize: 10),
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
                              color: MatrixTheme.matrixAccent,
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
                              color: MatrixTheme.matrixGreen
                                  .withValues(alpha: 0.9),
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.9;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: sheetHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MatrixTheme.terminalBlack.withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(
              color: MatrixTheme.matrixGreen.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: MatrixTheme.matrixAccent.withValues(alpha: 0.15),
                blurRadius: 20,
              ),
            ],
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
                    color: MatrixTheme.matrixDarkGreen.withValues(alpha: 0.55),
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
                        '> MEDIA // OBJECT_STORE',
                        style: _RoomInfoTerminal.promptLabel(context),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: MatrixTheme.matrixGreen,
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: _RoomInfoTerminal.screenPadding.copyWith(
                  top: 0,
                  bottom: 10,
                ),
                child: _buildFileFilterBar(),
              ),
              Expanded(
                child: _buildFilesList(),
              ),
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
    required this.loadThumbnail,
    required this.extLower,
  });

  final RoomFileItem item;
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
    final useThumb = kind == RoomMessageKind.image ||
        kind == RoomMessageKind.video ||
        kind == RoomMessageKind.file;
    try {
      var b = await widget.loadThumbnail(id, thumbnail: useThumb);
      if (b != null &&
          b.isNotEmpty &&
          useThumb &&
          !_isRoomInfoRasterBytes(b)) {
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
    const size = 40.0;
    const iconSize = 20.0;
    if (widget.item.eventId.isEmpty) {
      return _thumbShell(
        size,
        Icon(
          _roomFileIcon(widget.item.kind),
          size: iconSize,
          color: MatrixTheme.matrixDarkGreen,
        ),
      );
    }
    if (widget.item.kind == RoomMessageKind.audio) {
      return _thumbShell(
        size,
        Icon(
          Icons.audiotrack,
          size: iconSize,
          color: MatrixTheme.matrixAccent,
        ),
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
              color: MatrixTheme.matrixAccent,
            ),
          ),
        ),
      );
    }
    if (_bytes != null && _bytes!.isNotEmpty) {
      return _thumbShell(
        size,
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
              color: MatrixTheme.matrixDarkGreen,
            ),
          ),
        ),
      );
    }
    return _thumbShell(
      size,
      Icon(
        _roomFileIcon(widget.item.kind),
        size: iconSize,
        color: MatrixTheme.matrixDarkGreen,
      ),
    );
  }

  Widget _thumbShell(double size, Widget child) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        color: MatrixTheme.terminalBackground.withValues(alpha: 0.85),
      ),
      child: child,
    );
  }
}
