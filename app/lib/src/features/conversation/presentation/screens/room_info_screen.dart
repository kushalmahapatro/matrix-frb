import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/src/core/calls/matrix_call_launcher.dart';
import 'package:matrix/src/core/avatar_image_normalize.dart';
import 'package:matrix/src/core/desktop/desktop_esc_scope.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:matrix/src/core/open_in_app_url.dart';
import 'package:matrix/src/core/muted_chats_store.dart';
import 'package:matrix/src/core/network/network_availability.dart';
import 'package:matrix/src/core/timeline_local_hidden_store.dart';
import 'package:matrix/src/core/timeline_raster_thumb.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/conversation/presentation/widgets/link_preview_cards.dart';
import 'package:matrix/src/features/conversation/domain/services/conversation_service.dart';
import 'package:matrix/src/features/conversation/presentation/widgets/attachment_viewer.dart';
import 'package:matrix/src/features/settings/presentation/screens/profile_avatar_crop_screen.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix_sdk/matrix_sdk.dart';
import 'package:provider/provider.dart';
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

bool _isValidMatrixUserId(String raw) {
  final s = raw.trim();
  return RegExp(r'^@[^:@\s]+:[^\s:]+$').hasMatch(s);
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
    case RoomMessageKind.call:
      return Icons.call_outlined;
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
  StreamSubscription<List<Message>>? _timelineListSub;
  StreamSubscription<RoomUpdate>? _roomUpdateSub;
  Timer? _debouncedReload;

  @override
  void initState() {
    super.initState();
    unawaited(MutedChatsStore.instance.ensureLoaded());
    unawaited(_loadDetails());
    _timelineListSub = _service
        .subscribeToTimelineList(widget.roomId)
        .listen((_) => _scheduleDetailsReload());
    _roomUpdateSub = _service.subscribeToAllRoomUpdates().listen((u) {
      if (u.roomId == widget.roomId) _scheduleDetailsReload();
    });
  }

  @override
  void dispose() {
    _debouncedReload?.cancel();
    unawaited(_timelineListSub?.cancel());
    unawaited(_roomUpdateSub?.cancel());
    super.dispose();
  }

  void _scheduleDetailsReload() {
    _debouncedReload?.cancel();
    _debouncedReload = Timer(const Duration(milliseconds: 500), () {
      if (mounted) unawaited(_loadDetails(showLoading: false));
    });
  }

  Future<void> _loadDetails({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final r = await _service.getRoomDetails(widget.roomId);
    r.fold(
      (d) {
        if (!mounted) return;
        setState(() {
          _details = d;
          _loading = false;
          _error = null;
        });
      },
      (f) {
        if (!mounted) return;
        if (showLoading) {
          final offline = !context.read<NetworkAvailability>().isOnline;
          setState(() {
            _error = offline
                ? 'No internet connection. Connect to refresh the latest room details from the server.'
                : f.toString();
            _loading = false;
          });
        } else {
          setState(() => _loading = false);
        }
      },
    );
  }

  Future<void> _pickAndUploadGroupAvatar() async {
    final d = _details;
    if (d == null || !d.currentUserCanSetRoomAvatar) return;
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    if (x == null || !mounted) return;
    final rawBytes = await x.readAsBytes();
    if (rawBytes.isEmpty) return;
    final forCrop = normalizeAvatarImageBytes(rawBytes, x.path) ?? rawBytes;
    if (!mounted) return;
    final cropped = await Navigator.of(context).push<Uint8List?>(
      MaterialPageRoute<Uint8List?>(
        fullscreenDialog: true,
        builder: (ctx) => ProfileAvatarCropScreen(
          imageBytes: forCrop,
          title: 'CROP ROOM IMAGE',
          hintText:
              'Pinch and drag to frame the room image. The square is what everyone sees in the room list.',
        ),
      ),
    );
    if (cropped == null || cropped.isEmpty) return;
    final uploadBytes =
        normalizeAvatarImageBytes(cropped, 'crop.jpg') ?? cropped;
    const mime = 'image/jpeg';
    final r = await _service.uploadRoomAvatar(
      roomId: widget.roomId,
      mimeType: mime,
      data: uploadBytes,
    );
    if (!mounted) return;
    r.fold(
      (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Room image updated')));
        unawaited(_loadDetails(showLoading: false));
      },
      (f) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not set room image: $f'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
    );
  }

  Future<void> _removeGroupAvatar() async {
    final d = _details;
    if (d == null || !d.currentUserCanSetRoomAvatar) return;
    if (d.roomAvatarUrl.trim().isEmpty) return;
    final r = await _service.removeRoomAvatar(roomId: widget.roomId);
    if (!mounted) return;
    r.fold(
      (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Room image removed')));
        unawaited(_loadDetails(showLoading: false));
      },
      (f) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not remove room image: $f'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
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
        unawaited(_loadDetails(showLoading: false));
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

  Future<void> _ban(RoomMemberRow m) async {
    final ok = await _terminalConfirm(
      title: 'ban_user',
      body:
          'Ban ${m.displayName}? They will be removed and blocked from re-joining until unbanned.',
      confirmLabel: 'BAN',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final r = await _service.banRoomMember(
      roomId: widget.roomId,
      userId: m.userId,
    );
    r.fold(
      (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${m.displayName} was banned')));
        unawaited(_loadDetails(showLoading: false));
      },
      (f) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ban failed: $f'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
    );
  }

  Future<void> _unban(RoomBannedUserRow b) async {
    final ok = await _terminalConfirm(
      title: 'unban_user',
      body: 'Remove the ban for ${b.displayName}? They can be invited again.',
      confirmLabel: 'UNBAN',
    );
    if (ok != true || !mounted) return;
    final r = await _service.unbanRoomMember(
      roomId: widget.roomId,
      userId: b.userId,
    );
    r.fold(
      (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unbanned ${b.displayName}')));
        unawaited(_loadDetails(showLoading: false));
      },
      (f) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unban failed: $f'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
    );
  }

  Future<void> _showInviteMemberSheet(ThemeData theme) async {
    final d = _details;
    if (d != null && !d.currentUserCanInvite) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Your power level is below the room's invite requirement (≥ ${d.powerLevelInviteRequired}).",
          ),
        ),
      );
      return;
    }
    await _presentRoomInfoAuxiliary(
      (sheetCtx) => _InviteMemberSheet(
        theme: theme,
        service: _service,
        rootContext: context,
        onClose: () => Navigator.of(sheetCtx).pop(),
        onInviteUserId: _inviteUserById,
      ),
    );
  }

  Future<void> _inviteUserById(String userId) async {
    final r = await _service.inviteUserToRoom(
      roomId: widget.roomId,
      userId: userId,
    );
    if (!mounted) return;
    r.fold(
      (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Invite sent to $userId')));
        unawaited(_loadDetails(showLoading: false));
      },
      (f) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invite failed: $f'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
    );
  }

  Future<void> _applyInvitePowerLevel(int inviteRequired) async {
    final r = await _service.applyRoomPowerLevelSettings(
      roomId: widget.roomId,
      patch: RoomPowerLevelSettingsPatch(invite: inviteRequired),
    );
    if (!mounted) return;
    r.fold(
      (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room invite rules updated')),
        );
        unawaited(_loadDetails(showLoading: false));
      },
      (f) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $f'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
    );
  }

  void _showRoomPermissionsSheet(ThemeData theme) {
    final d = _details!;
    unawaited(
      _presentRoomInfoAuxiliary(
        (sheetContext) => _RoomPermissionsSheet(
          sheetContext: sheetContext,
          theme: theme,
          details: d,
          onSetInviteLevel: _applyInvitePowerLevel,
        ),
      ),
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
        unawaited(_loadDetails(showLoading: false));
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
          icon: const Icon(Icons.call_outlined),
          onPressed: _details == null
              ? null
              : () {
                  final d = _details!;
                  unawaited(
                    showMatrixCallOptionsSheet(
                      context: context,
                      roomId: widget.roomId,
                      roomName: d.displayName.isNotEmpty
                          ? d.displayName
                          : widget.roomId,
                      isDirectRoom: d.isDirect,
                    ),
                  );
                },
          tooltip: 'Call',
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => unawaited(_loadDetails()),
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
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => unawaited(
            showMatrixCallOptionsSheet(
              context: context,
              roomId: widget.roomId,
              roomName: d.displayName.isNotEmpty ? d.displayName : widget.roomId,
              isDirectRoom: d.isDirect,
            ),
          ),
          icon: const Icon(Icons.call_outlined, size: 20),
          label: Text(d.isDirect ? 'CALL OPTIONS' : 'GROUP CALL OPTIONS'),
        ),
        const SizedBox(height: 12),
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
        if (!d.isDirect) ...[
          const SizedBox(height: 16),
          _RoomInfoGroupAvatarBlock(
            theme: theme,
            roomAvatarMxc: d.roomAvatarUrl,
            canChange: d.currentUserCanSetRoomAvatar,
            onPickImage: _pickAndUploadGroupAvatar,
            onRemoveImage: d.roomAvatarUrl.trim().isNotEmpty
                ? _removeGroupAvatar
                : null,
            fetchThumbnail: (mxc) async {
              final r = await _service.fetchUserAvatarThumbnail(mxcUri: mxc);
              return r.fold((b) => b, (_) => null);
            },
          ),
        ],
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
                      'Members: ${d.memberCount}'
                      '${d.invitedMembers.isEmpty ? '' : ' · Invited: ${d.invitedMembers.length}'} · '
                      '${d.isDirect ? "Direct" : "Group"}'
                      '${d.isDirect ? "" : " · invite PL ≥ ${d.powerLevelInviteRequired}"}',
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
          countLabel: '${d.mediaIndexCount}',
          onTap: () => _showMediaBottomSheet(theme),
        ),
        _roomLinkRow(
          theme,
          label: 'Links',
          icon: Icons.link_outlined,
          countLabel: '${d.linksIndexCount}',
          onTap: () => _showLinksBottomSheet(theme),
        ),
        if (!d.isDirect)
          _roomLinkRow(
            theme,
            label: 'Polls',
            icon: Icons.poll_outlined,
            countLabel: '${d.pollsIndexCount}',
            onTap: () => _showPollsBottomSheet(theme),
          ),
        _muteChatOptionRow(theme),
        _roomLinkRow(
          theme,
          label: 'Actions',
          icon: Icons.bolt_outlined,
          onTap: _showActionsBottomSheet,
        ),
        if (!d.isDirect && d.currentUserIsAdmin)
          _roomLinkRow(
            theme,
            label: 'Room permissions',
            icon: Icons.admin_panel_settings_outlined,
            onTap: () => _showRoomPermissionsSheet(theme),
          ),
        if (!d.isDirect) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'MEMBERS',
                      style: _RoomInfoStyles.sectionHeader(theme),
                    ),
                    _RoomInfoStyles.sectionDivider(theme),
                  ],
                ),
              ),
              if (d.currentUserCanInvite)
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 2),
                  child: TextButton.icon(
                    onPressed: () => unawaited(_showInviteMemberSheet(theme)),
                    icon: Icon(
                      Icons.person_add_outlined,
                      size: 18,
                      color: scheme.primary,
                    ),
                    label: Text(
                      'INVITE',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!d.currentUserCanInvite)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Only members with power ≥ ${d.powerLevelInviteRequired} can invite '
                '(your client hides the invite action when the server would reject it).',
                style: _RoomInfoStyles.captionMuted(theme),
              ),
            ),
          if (d.members.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Member list will appear after sync.',
                style: _RoomInfoStyles.captionMuted(theme),
              ),
            )
          else
            ...d.members.map((m) => _memberTile(theme, d, m)),
          if (d.invitedMembers.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'INVITED (PENDING)',
              style: _RoomInfoStyles.sectionHeader(theme),
            ),
            _RoomInfoStyles.sectionDivider(theme),
            const SizedBox(height: 8),
            Text(
              'These users have been invited but have not joined yet. '
              'Shown from your local copy of the room state (works offline when already synced).',
              style: _RoomInfoStyles.captionMuted(theme),
            ),
            const SizedBox(height: 10),
            ...d.invitedMembers.map((i) => _invitedMemberTile(theme, i)),
          ],
          if (d.bannedUsers.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('BANNED', style: _RoomInfoStyles.sectionHeader(theme)),
            _RoomInfoStyles.sectionDivider(theme),
            const SizedBox(height: 8),
            ...d.bannedUsers.map((b) => _bannedUserTile(theme, d, b)),
          ],
        ],
      ],
    );
  }

  /// Mute / unmute for this room (local badge + notification suppression).
  Widget _muteChatOptionRow(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: ValueListenableBuilder<Set<String>>(
        valueListenable: MutedChatsStore.instance.ids,
        builder: (context, mutedIds, _) {
          final muted = mutedIds.contains(widget.roomId);
          Future<void> applyMuted(bool v) async {
            await MutedChatsStore.instance.setMuted(widget.roomId, v);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  v
                      ? 'Chat muted — no unread count or notifications'
                      : 'Chat unmuted',
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => unawaited(applyMuted(!muted)),
                      borderRadius: BorderRadius.circular(4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: scheme.primary,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              muted
                                  ? Icons.notifications_off_outlined
                                  : Icons.notifications_outlined,
                              color: scheme.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Mute chat',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'No unread badge in the room list and no notifications '
                                  'for this room on this device.',
                                  style: _RoomInfoStyles.captionMuted(theme),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: muted,
                  onChanged: (v) => unawaited(applyMuted(v)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _roomLinkRow(
    ThemeData theme, {
    required String label,
    required IconData icon,
    String? countLabel,
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
            if (countLabel != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  countLabel,
                  style: _RoomInfoStyles.captionMuted(
                    theme,
                  ).copyWith(fontWeight: FontWeight.w700),
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

  Widget _bannedUserTile(ThemeData theme, RoomDetails d, RoomBannedUserRow b) {
    final scheme = theme.colorScheme;
    final canUnban = d.currentUserCanBan;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(
                color: scheme.error.withValues(alpha: 0.85),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.block, color: scheme.error, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.displayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  b.userIdDisplay,
                  style: _RoomInfoStyles.captionMuted(
                    theme,
                  ).copyWith(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (canUnban)
            TextButton(
              onPressed: () => _unban(b),
              child: Text(
                'UNBAN',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _memberTile(ThemeData theme, RoomDetails d, RoomMemberRow m) {
    final admin = d.currentUserIsAdmin;
    final showMenu =
        !m.isSelf && (admin || m.currentUserCanKick || m.currentUserCanBan);
    final scheme = theme.colorScheme;
    final Color? roleAccent = switch (m.role) {
      RoomMemberRoleDto.creator => const Color(0xFFFFC107),
      RoomMemberRoleDto.administrator => scheme.primary,
      RoomMemberRoleDto.moderator => scheme.tertiary,
      RoomMemberRoleDto.user => null,
    };
    final borderColor = roleAccent ?? scheme.primary;
    final borderW = roleAccent != null ? 2.0 : 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: roleAccent != null ? const EdgeInsets.all(10) : EdgeInsets.zero,
      decoration: roleAccent != null
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: roleAccent.withValues(alpha: 0.85),
                width: 1.5,
              ),
              color: roleAccent.withValues(alpha: 0.06),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: borderW),
              borderRadius: BorderRadius.circular(4),
            ),
            clipBehavior: Clip.antiAlias,
            child: _RoomMemberMxcAvatar(
              theme: theme,
              mxcUri: m.avatarUrl,
              fetchThumbnail: (mxc) async {
                final r = await _service.fetchUserAvatarThumbnail(mxcUri: mxc);
                return r.fold((b) => b, (_) => null);
              },
            ),
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
                    if (m.role != RoomMemberRoleDto.user) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: (roleAccent ?? scheme.primary).withValues(
                              alpha: 0.75,
                            ),
                          ),
                          color: (roleAccent ?? scheme.primary).withValues(
                            alpha: 0.12,
                          ),
                        ),
                        child: Text(
                          _roleLabel(m.role).toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 8,
                            letterSpacing: 0.5,
                            color: roleAccent ?? scheme.primary,
                          ),
                        ),
                      ),
                    ],
                    if (m.isSelf)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
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
                  case 'ban':
                    if (m.currentUserCanBan) await _ban(m);
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
                if (m.currentUserCanBan)
                  const PopupMenuItem(value: 'ban', child: Text('Ban')),
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

  Widget _invitedMemberTile(ThemeData theme, RoomInvitedMemberRow i) {
    final scheme = theme.colorScheme;
    final hasAvatar = i.avatarUrl.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: scheme.primary.withValues(alpha: 0.65)),
              borderRadius: BorderRadius.circular(4),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasAvatar
                ? _RoomMemberMxcAvatar(
                    theme: theme,
                    mxcUri: i.avatarUrl,
                    fetchThumbnail: (mxc) async {
                      final r = await _service.fetchUserAvatarThumbnail(
                        mxcUri: mxc,
                      );
                      return r.fold((b) => b, (_) => null);
                    },
                  )
                : Icon(Icons.mail_outline, color: scheme.primary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i.displayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  i.userIdDisplay,
                  style: _RoomInfoStyles.captionMuted(
                    theme,
                  ).copyWith(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Pending invite',
                  style: _RoomInfoStyles.captionMuted(theme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomInfoGroupAvatarBlock extends StatefulWidget {
  const _RoomInfoGroupAvatarBlock({
    required this.theme,
    required this.roomAvatarMxc,
    required this.canChange,
    required this.onPickImage,
    this.onRemoveImage,
    required this.fetchThumbnail,
  });

  final ThemeData theme;
  final String roomAvatarMxc;
  final bool canChange;
  final VoidCallback onPickImage;
  final VoidCallback? onRemoveImage;
  final Future<Uint8List?> Function(String mxcUri) fetchThumbnail;

  @override
  State<_RoomInfoGroupAvatarBlock> createState() =>
      _RoomInfoGroupAvatarBlockState();
}

class _RoomInfoGroupAvatarBlockState extends State<_RoomInfoGroupAvatarBlock> {
  Uint8List? _bytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _RoomInfoGroupAvatarBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomAvatarMxc != widget.roomAvatarMxc) {
      _bytes = null;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final mxc = widget.roomAvatarMxc.trim();
    if (mxc.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    final b = await widget.fetchThumbnail(mxc);
    if (!mounted) return;
    setState(() {
      _bytes = b;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.theme.colorScheme;
    final mxc = widget.roomAvatarMxc.trim();
    final hasImg = _bytes != null && _bytes!.isNotEmpty;

    Widget avatarContent;
    if (_loading && mxc.isNotEmpty) {
      avatarContent = Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: scheme.primary,
          ),
        ),
      );
    } else if (hasImg) {
      avatarContent = Image.memory(
        _bytes!,
        width: 88,
        height: 88,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else {
      avatarContent = Icon(
        Icons.group_outlined,
        color: scheme.primary,
        size: 36,
      );
    }

    final tile = Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.primary, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarContent,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.canChange)
          GestureDetector(
            onTap: widget.onPickImage,
            onLongPress: widget.onRemoveImage,
            child: tile,
          )
        else
          tile,
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('GROUP IMAGE', style: _RoomInfoStyles.prompt(widget.theme)),
              const SizedBox(height: 6),
              Text(
                widget.canChange
                    ? 'Tap to choose a new image. Long-press to remove.'
                    : 'Only members allowed to change the room avatar can update this.',
                style: _RoomInfoStyles.captionMuted(widget.theme),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoomMemberMxcAvatar extends StatefulWidget {
  const _RoomMemberMxcAvatar({
    required this.theme,
    required this.mxcUri,
    required this.fetchThumbnail,
  });

  final ThemeData theme;
  final String mxcUri;
  final Future<Uint8List?> Function(String mxcUri) fetchThumbnail;

  @override
  State<_RoomMemberMxcAvatar> createState() => _RoomMemberMxcAvatarState();
}

class _RoomMemberMxcAvatarState extends State<_RoomMemberMxcAvatar> {
  Uint8List? _bytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _RoomMemberMxcAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mxcUri != widget.mxcUri) {
      _bytes = null;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final mxc = widget.mxcUri.trim();
    if (mxc.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    final b = await widget.fetchThumbnail(mxc);
    if (!mounted) return;
    setState(() {
      _bytes = b;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.theme.colorScheme;
    final mxc = widget.mxcUri.trim();
    if (_loading && mxc.isNotEmpty) {
      return Center(
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: scheme.primary,
          ),
        ),
      );
    }
    if (_bytes != null && _bytes!.isNotEmpty) {
      return Image.memory(
        _bytes!,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    return Icon(Icons.person, color: scheme.primary, size: 20);
  }
}

class _RoomPermissionsSheet extends StatelessWidget {
  const _RoomPermissionsSheet({
    required this.sheetContext,
    required this.theme,
    required this.details,
    required this.onSetInviteLevel,
  });

  final BuildContext sheetContext;
  final ThemeData theme;
  final RoomDetails details;
  final Future<void> Function(int level) onSetInviteLevel;

  @override
  Widget build(BuildContext context) {
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
          child: SingleChildScrollView(
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
                  'ROOM PERMISSIONS',
                  style: _RoomInfoStyles.sectionHeader(theme),
                ),
                const SizedBox(height: 10),
                Text(
                  'Matrix rooms use power levels (`m.room.power_levels`). '
                  'Here you can set the minimum power required to invite new members. '
                  'Typical values: 0 = any member, 50 = moderators+, 100 = admins only.',
                  style: _RoomInfoStyles.bodyMuted(theme),
                ),
                const SizedBox(height: 14),
                Text(
                  'Current invite ≥ ${details.powerLevelInviteRequired} · '
                  'kick ≥ ${details.powerLevelKickRequired} · '
                  'ban ≥ ${details.powerLevelBanRequired}',
                  style: _RoomInfoStyles.captionMuted(theme),
                ),
                const SizedBox(height: 16),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Allow members to add participants',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'When on, any joined member (power ≥ 0) can invite. '
                    'When off, the minimum invite power is 50 (moderators by default). '
                    'Use the buttons below for admins-only (100) or other tweaks.',
                    style: _RoomInfoStyles.captionMuted(theme),
                  ),
                  value: details.powerLevelInviteRequired <= 0,
                  onChanged: (v) {
                    Navigator.of(sheetContext).pop();
                    unawaited(onSetInviteLevel(v ? 0 : 50));
                  },
                ),
                const SizedBox(height: 12),
                Text('WHO CAN INVITE', style: _RoomInfoStyles.prompt(theme)),
                const SizedBox(height: 10),
                TerminalButton(
                  text: 'ANY MEMBER (POWER 0)',
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(onSetInviteLevel(0));
                  },
                  isPrimary: false,
                  icon: Icons.groups_outlined,
                ),
                const SizedBox(height: 8),
                TerminalButton(
                  text: 'MODERATORS+ (50)',
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(onSetInviteLevel(50));
                  },
                  isPrimary: false,
                  icon: Icons.shield_outlined,
                ),
                const SizedBox(height: 8),
                TerminalButton(
                  text: 'ADMINS ONLY (100)',
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(onSetInviteLevel(100));
                  },
                  isPrimary: false,
                  icon: Icons.lock_outline,
                ),
              ],
            ),
          ),
        ),
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
      case RoomMessageKind.call:
        return 'Call';
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
  RasterPreviewMeta? _rasterMeta;
  Size _frameSize = const Size(
    kTimelineThumbPortraitW,
    kTimelineThumbPortraitH,
  );
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
      _frameSize = const Size(kTimelineThumbPortraitW, kTimelineThumbPortraitH);
      _rasterMeta = null;
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
      RasterPreviewMeta? meta;
      Size frame = const Size(kTimelineThumbPortraitW, kTimelineThumbPortraitH);
      if (b != null && b.isNotEmpty && useThumb) {
        meta = await decodeRasterPreviewMeta(b);
        if (meta != null) {
          frame = timelineThumbFrameSizeFromPreviewMeta(meta);
          final longLogical = frame.width >= frame.height
              ? frame.width
              : frame.height;
          final longPx = timelineThumbDecodeExtentPx(longLogical);
          final small = await encodeRasterPngMaxLongEdgeWithMeta(
            b,
            longPx,
            meta,
          );
          if (small != null) b = small;
        } else {
          final longPx = timelineThumbDecodeExtentPx(
            frame.width >= frame.height ? frame.width : frame.height,
          );
          final small = await encodeRasterPngFitBox(
            b,
            targetWidthPx: longPx,
            targetHeightPx: longPx,
          );
          if (small != null) b = small;
        }
      }
      if (!mounted) return;
      setState(() {
        _bytes = b;
        _rasterMeta = meta;
        _frameSize = frame;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bytes = null;
        _rasterMeta = null;
        _frameSize = const Size(
          kTimelineThumbPortraitW,
          kTimelineThumbPortraitH,
        );
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.theme.colorScheme;
    final tw = _frameSize.width;
    final th = _frameSize.height;
    final thumbDecode = timelineThumbImageDecodeCacheParams(
      logicalWidth: tw,
      logicalHeight: th,
      context: context,
    );
    const iconSize = 20.0;
    final dim = scheme.onSurface.withValues(alpha: 0.55);
    if (widget.item.eventId.isEmpty) {
      return _thumbShell(
        tw,
        th,
        scheme,
        Icon(_roomFileIcon(widget.item.kind), size: iconSize, color: dim),
      );
    }
    if (widget.item.kind == RoomMessageKind.audio) {
      return _thumbShell(
        tw,
        th,
        scheme,
        Icon(Icons.audiotrack, size: iconSize, color: scheme.primary),
      );
    }
    if (_loading) {
      return SizedBox(
        width: tw,
        height: th,
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
      Widget thumbDecodeError(_, Object __, StackTrace? ___) =>
          Icon(_roomFileIcon(widget.item.kind), size: iconSize, color: dim);
      final turns = _rasterMeta != null
          ? exifQuarterTurns(_rasterMeta!.exifOrientation)
          : 0;
      final imageCore = turns == 0
          ? Image.memory(
              _bytes!,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              cacheWidth: thumbDecode.cacheWidth,
              cacheHeight: thumbDecode.cacheHeight,
              errorBuilder: thumbDecodeError,
            )
          : RotatedBox(
              quarterTurns: turns,
              child: Image.memory(
                _bytes!,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                cacheWidth: thumbDecode.cacheWidth,
                cacheHeight: thumbDecode.cacheHeight,
                errorBuilder: thumbDecodeError,
              ),
            );
      return _thumbShell(
        tw,
        th,
        scheme,
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            width: tw,
            height: th,
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              alignment: Alignment.center,
              child: imageCore,
            ),
          ),
        ),
      );
    }
    return _thumbShell(
      tw,
      th,
      scheme,
      Icon(_roomFileIcon(widget.item.kind), size: iconSize, color: dim),
    );
  }

  Widget _thumbShell(double w, double h, ColorScheme scheme, Widget child) {
    return Container(
      width: w,
      height: h,
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

/// Directory search + manual Matrix ID for room invites.
class _InviteMemberSheet extends StatefulWidget {
  const _InviteMemberSheet({
    required this.theme,
    required this.service,
    required this.rootContext,
    required this.onClose,
    required this.onInviteUserId,
  });

  final ThemeData theme;
  final ConversationService service;
  final BuildContext rootContext;
  final VoidCallback onClose;
  final Future<void> Function(String userId) onInviteUserId;

  @override
  State<_InviteMemberSheet> createState() => _InviteMemberSheetState();
}

class _InviteMemberSheetState extends State<_InviteMemberSheet> {
  final _searchCtrl = TextEditingController();
  final _manualCtrl = TextEditingController();
  Timer? _debounce;
  List<User> _results = [];
  bool _searching = false;

  /// `false` = directory search by name; `true` = invite by full Matrix ID.
  bool _inviteByMatrixId = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchTextChanged);
    _manualCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _onSearchTextChanged() {
    final raw = _searchCtrl.text;
    _debounce?.cancel();
    final q = raw.trim();
    if (q.length < 2) {
      if (_results.isNotEmpty || _searching) {
        setState(() {
          _results = [];
          _searching = false;
        });
      }
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), () => _runSearch(q));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchTextChanged);
    _searchCtrl.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String q) async {
    if (!mounted) return;
    setState(() => _searching = true);
    final r = await widget.service.searchUsers(query: q);
    if (!mounted) return;
    r.fold(
      (ok) => setState(() {
        _results = ok.users;
        _searching = false;
      }),
      (_) => setState(() {
        _results = [];
        _searching = false;
      }),
    );
  }

  void _pickUser(User u) {
    widget.onClose();
    unawaited(widget.onInviteUserId(u.userId));
  }

  void _inviteManual() {
    final raw = _manualCtrl.text;
    if (!_isValidMatrixUserId(raw)) {
      final s = Theme.of(widget.rootContext).colorScheme;
      ScaffoldMessenger.of(widget.rootContext).showSnackBar(
        SnackBar(
          content: Text(
            'Enter a full Matrix ID like @user:server',
            style: TextStyle(color: s.onError),
          ),
          backgroundColor: s.error,
        ),
      );
      return;
    }
    widget.onClose();
    unawaited(widget.onInviteUserId(raw.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final scheme = theme.colorScheme;
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    return Align(
      alignment: Alignment.bottomCenter,
      child: DesktopEscScope(
        child: SizedBox(
          height: screenH * 0.88,
          child: TerminalContainer(
            showBorder: true,
            showGlow: false,
            borderColor: scheme.primary,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'INVITE MEMBER',
                          style: _RoomInfoStyles.sectionHeader(theme),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        color: scheme.primary,
                        tooltip: 'Close',
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Invite by Matrix ID',
                      style: _RoomInfoStyles.prompt(theme),
                    ),
                    subtitle: Text(
                      _inviteByMatrixId
                          ? 'Enter @user:server, then send invite.'
                          : 'Search your homeserver directory by name.',
                      style: _RoomInfoStyles.captionMuted(theme),
                    ),
                    value: _inviteByMatrixId,
                    onChanged: (v) {
                      setState(() {
                        _inviteByMatrixId = v;
                        if (v) {
                          _debounce?.cancel();
                          _results = [];
                          _searching = false;
                        }
                      });
                      if (!v) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          final q = _searchCtrl.text.trim();
                          if (q.length >= 2) unawaited(_runSearch(q));
                        });
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    key: ValueKey<bool>(_inviteByMatrixId),
                    controller: _inviteByMatrixId ? _manualCtrl : _searchCtrl,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: _inviteByMatrixId
                          ? '@user:example.org'
                          : 'Name or @user:server',
                      hintStyle: _RoomInfoStyles.captionMuted(theme),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: scheme.primary.withValues(alpha: 0.55),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: scheme.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    autocorrect: !_inviteByMatrixId,
                    keyboardType: _inviteByMatrixId
                        ? TextInputType.emailAddress
                        : TextInputType.text,
                    textInputAction: _inviteByMatrixId
                        ? TextInputAction.done
                        : TextInputAction.search,
                    onSubmitted: (_) {
                      if (_inviteByMatrixId) {
                        _inviteManual();
                      }
                    },
                    scrollPadding: EdgeInsets.only(
                      bottom:
                          (_inviteByMatrixId ? 120 : 24) + mq.padding.bottom,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (!_inviteByMatrixId)
                  Expanded(
                    child: _searching
                        ? const Center(child: CircularProgressIndicator())
                        : _results.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'Type at least two characters to search.',
                              style: _RoomInfoStyles.bodyMuted(theme),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: scheme.outline.withValues(alpha: 0.25),
                            ),
                            itemBuilder: (ctx, i) {
                              final u = _results[i];
                              final dn = u.displayName?.trim();
                              final label = (dn != null && dn.isNotEmpty)
                                  ? dn
                                  : u.userIdDisplay;
                              return ListTile(
                                title: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  u.userIdDisplay,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _RoomInfoStyles.captionMuted(theme),
                                ),
                                onTap: () => _pickUser(u),
                              );
                            },
                          ),
                  )
                else
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Text(
                          'Full user ID including homeserver (e.g. @alice:matrix.org).',
                          style: _RoomInfoStyles.bodyMuted(theme),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                if (_inviteByMatrixId)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      8,
                      20,
                      20 + mq.padding.bottom,
                    ),
                    child: TerminalButton(
                      text: 'SEND INVITE',
                      onPressed: _manualCtrl.text.trim().isEmpty
                          ? null
                          : _inviteManual,
                      isPrimary: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
