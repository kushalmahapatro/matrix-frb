import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/desktop/desktop_dialog_flow.dart';
import 'package:matrix/src/core/desktop/desktop_shell_scope.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/desktop/desktop_window_coordinator.dart';
import 'package:matrix/src/core/layout/app_layout_variant.dart';
import 'package:matrix/src/core/layout/app_layout_actions.dart';
import 'package:matrix/src/core/layout/messaging_layout_preference.dart';
import 'package:matrix/src/core/muted_chats_store.dart';
import 'package:provider/provider.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix/src/core/network/network_availability.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/state_management/base_state_widget_model.dart';
import 'package:matrix/src/core/timeline_local_hidden_store.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:matrix/src/features/create_chat/presentation/screens/create_chat_screen.dart';
import 'package:matrix/src/features/messaging/domain/messaging_room_list_model.dart';
import 'package:matrix/src/features/messaging/presentation/screens/messaging_workspace_screen.dart';
import 'package:matrix/src/features/settings/domain/profile_local_cache.dart';
import 'package:matrix/src/features/settings/domain/profile_prefs.dart';
import 'package:matrix/src/features/key_recovery/domain/key_recovery_prefs.dart';
import 'package:matrix/src/features/key_recovery/presentation/screens/login_recovery_unlock_screen.dart';
import 'package:matrix/src/features/key_recovery/presentation/screens/setup_key_recovery_screen.dart';
import 'package:matrix/src/features/settings/presentation/screens/settings_screen.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix_sdk/matrix_sdk.dart' show Message;

class MessagingWorkspaceWM
    extends BaseWidgetModel<MessagingWorkspaceScreen, MessagingRoomListModel>
    implements DesktopShellLauncher {
  MessagingWorkspaceWM(super.model);

  final GlobalKey<NavigatorState> nestedNavigatorKey =
      GlobalKey<NavigatorState>();

  @override
  NavigatorState? get nestedShellNavigator => nestedNavigatorKey.currentState;

  final ValueNotifier<ChatState> chatState = ValueNotifier(
    const ChatState.loading(),
  );
  final ValueNotifier<ChatType> selectedChatType = ValueNotifier(ChatType.all);
  final ValueNotifier<Chat?> selectedRoom = ValueNotifier<Chat?>(null);

  /// Compact (phone) home: 0 = Chats, 1 = Calls.
  final ValueNotifier<int> mobileHomeTabIndex = ValueNotifier(0);

  /// Desktop split / narrow-desktop shell: 0 = Chats, 1 = Calls (sidebar or compact pane).
  final ValueNotifier<int> desktopSidebarTabIndex = ValueNotifier(0);

  /// Filters the room list (name, last line, id). Notifies on each keystroke.
  late final TextEditingController roomListSearchController;

  /// Keyboard highlight in the room list (desktop). Separate from [selectedRoom].
  final ValueNotifier<String?> roomListKeyboardFocusId = ValueNotifier<String?>(
    null,
  );

  /// Empty until first [refreshRecoveryBannerState] completes; then SDK label.
  final ValueNotifier<String> recoveryBannerState = ValueNotifier<String>('');

  final ValueNotifier<bool> recoveryBannerDismissedThisSession =
      ValueNotifier<bool>(false);

  /// Persisted “don’t show again” after user checks the box and acts on the banner.
  final ValueNotifier<bool> recoveryBannerDontShowAgainPersisted =
      ValueNotifier<bool>(false);

  /// From [MatrixClient.backupExistsOnServer] after refresh (false if check failed).
  final ValueNotifier<bool> recoveryServerBackupExists =
      ValueNotifier<bool>(false);

  final FocusNode roomListFocusNode = FocusNode(debugLabel: 'roomList');

  /// Unlock screen when keys are incomplete, or server already has a backup (even if local state is "disabled").
  bool get preferUnlockRecoveryBanner {
    final s = recoveryBannerState.value;
    if (s == 'incomplete') return true;
    return recoveryServerBackupExists.value;
  }

  bool get shouldShowRecoveryBanner {
    final s = recoveryBannerState.value;
    if (s.isEmpty || s == 'enabled') return false;
    if (recoveryBannerDismissedThisSession.value) return false;
    if (recoveryBannerDontShowAgainPersisted.value) return false;
    return true;
  }

  Future<void> _applyBannerDontShowAgain(bool dontShowAgain) async {
    if (!dontShowAgain) return;
    recoveryBannerDontShowAgainPersisted.value = true;
    recoveryBannerDismissedThisSession.value = true;
    await KeyRecoveryPrefs.setBannerDontShowAgain(true);
  }

  StreamSubscription<List<Chat>>? _roomListSubscription;
  bool _isSubscribed = false;

  void _onSelectedRoomForTypingResync() {
    chatState.value.maybeWhen(
      loaded: _syncTypingSubscriptionsForRooms,
      orElse: () {},
    );
  }
  Timer? _reconnectionTimer;
  Timer? _healthCheckTimer;
  int _reconnectionAttempts = 0;
  DateTime? _lastUpdateTime;
  static const int _maxReconnectionAttempts = 10;
  static const Duration _initialReconnectionDelay = Duration(seconds: 1);
  static const Duration _maxReconnectionDelay = Duration(seconds: 30);
  static const Duration _healthCheckInterval = Duration(seconds: 30);

  Timer? _emptyRoomListSettleTimer;
  static const Duration _emptyListSettleDuration = Duration(milliseconds: 1200);

  AppLayoutVariant? _lastLayout;

  AppLayoutVariant _variant(BuildContext context) {
    final mq = MediaQuery.of(context);
    MessagingLayoutPreference pref;
    try {
      pref = Provider.of<MessagingLayoutPreferenceNotifier>(
        context,
        listen: false,
      ).value;
    } catch (_) {
      pref = MessagingLayoutPreference.auto;
    }
    return resolveMessagingLayoutVariant(mq: mq, preference: pref);
  }

  /// Same [layout] the shell used to build split vs compact ([_MessagingBody.variant]).
  /// Do not infer from an arbitrary [BuildContext]: nested contexts can disagree with
  /// the shell and route taps through the wrong policy (e.g. split UI + compact open).
  AppLayoutActions _actionsFor(AppLayoutVariant layout) {
    if (layout == AppLayoutVariant.compact) {
      return CompactLayoutActions(
        pushConversation: (ctx, chat) => _pushConversationCompact(ctx, chat),
        pushCreate: openCreateChat,
        pushSettings: (ctx) => unawaited(openSettingsFrom(ctx)),
        openRoomInNewWindowImpl: (ctx, chat) =>
            unawaited(_openDesktopConversation(ctx, chat)),
      );
    }
    return SplitLayoutActions(
      onSelectRoom: (chat) => selectedRoom.value = chat,
      pushCreate: openCreateChat,
      pushSettings: (ctx) => unawaited(openSettingsFrom(ctx)),
      openRoomInNewWindowImpl: (ctx, chat) =>
          unawaited(_openDesktopConversation(ctx, chat)),
    );
  }

  @override
  Future<T?> openShellFlow<T extends Object?>({
    required BuildContext anchorContext,
    required Widget page,
    String? windowTitle,
    Size preferredWindowSize = const Size(520, 720),
  }) async {
    if (!anchorContext.mounted) return null;
    if (isDesktopTargetPlatform() &&
        preferDialogOverModalSheet(anchorContext)) {
      return _presentInDesktopDialog<T>(anchorContext, page);
    }

    return NavigatorService.push<T>(anchorContext, page);
  }

  Future<T?> _presentInDesktopDialog<T extends Object?>(
    BuildContext anchorContext,
    Widget page,
  ) {
    final mq = MediaQuery.of(anchorContext);
    final loc = MaterialLocalizations.of(anchorContext);
    return showGeneralDialog<T>(
      context: anchorContext,
      barrierDismissible: true,
      barrierLabel: loc.modalBarrierDismissLabel,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return Dialog(
          backgroundColor: Theme.of(dialogContext).colorScheme.surface,
          elevation: 12,
          shadowColor: Colors.black54,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: scheme.outline.withValues(alpha: 0.28)),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 28,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 720,
              maxHeight: mq.size.height * 0.9,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: DesktopDialogFlowHost(page: page),
            ),
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (ctx, anim, sec, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }

  /// Create chat from any shell context (toolbar, compact stack, split list).
  Future<String?> openCreateChat(BuildContext anchorContext) =>
      openShellFlow<String?>(
        anchorContext: anchorContext,
        page: const CreateChatScreen(),
        windowTitle: 'New chat',
        preferredWindowSize: const Size(540, 720),
      );

  Future<void> openSettingsFrom(BuildContext anchorContext) async {
    await openShellFlow<Object?>(
      anchorContext: anchorContext,
      page: const SettingsScreen(),
      windowTitle: 'Settings',
      preferredWindowSize: const Size(520, 720),
    );
  }

  Future<void> _pushConversationCompact(BuildContext context, Chat chat) async {
    // Do not set [selectedRoom] here: that drives split-pane list selection only.
    // Setting it would highlight a row under the pushed route (visible on mobile).
    final nav = nestedNavigatorKey.currentState;
    if (nav == null) return;
    await nav.push(
      MaterialPageRoute<void>(
        builder: (c) => ConversationScreen(
          roomId: chat.id,
          roomName: chat.name,
          status: chat.status,
        ),
      ),
    );
    if (!context.mounted) return;
    if (_variant(context) == AppLayoutVariant.compact) {
      selectedRoom.value = null;
    }
  }

  Future<void> _openDesktopConversation(BuildContext context, Chat chat) async {
    final ok = await openConversationInNewDesktopWindow(
      context: context,
      chat: chat,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open a new window. Check desktop_multi_window runner '
            'integration (macOS / Windows / Linux).',
          ),
          duration: Duration(seconds: 10),
        ),
      );
    }
  }

  void onRoomTap(AppLayoutVariant shellLayout, Chat chat) {
    if (isDesktopTargetPlatform()) {
      roomListFocusNode.requestFocus();
      roomListKeyboardFocusId.value = chat.id;
    }
    _actionsFor(shellLayout).openRoom(context, chat);
  }

  void onRoomDoubleTap(AppLayoutVariant shellLayout, Chat chat) {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.linux &&
        defaultTargetPlatform != TargetPlatform.macOS &&
        defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }
    unawaited(_openDesktopConversation(context, chat));
  }

  /// Right-click room row — desktop context menu.
  Future<void> showRoomListContextMenu(
    BuildContext anchorContext,
    AppLayoutVariant shellLayout,
    Chat chat,
    Offset globalPosition,
  ) async {
    if (!isDesktopTargetPlatform()) return;
    if (!anchorContext.mounted) return;
    await MutedChatsStore.instance.ensureLoaded();
    if (!anchorContext.mounted) return;
    final muted = MutedChatsStore.instance.isMuted(chat.id);
    final canNewWindow =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows);
    final choice = await showMenu<String>(
      context: anchorContext,
      position: desktopMenuPositionAt(anchorContext, globalPosition),
      items: [
        const PopupMenuItem<String>(value: 'open', child: Text('Open')),
        if (canNewWindow)
          const PopupMenuItem<String>(
            value: 'window',
            child: Text('Open in new window'),
          ),
        PopupMenuItem<String>(
          value: muted ? 'unmute' : 'mute',
          child: Text(muted ? 'Unmute chat' : 'Mute chat'),
        ),
      ],
    );
    if (!anchorContext.mounted) return;
    switch (choice) {
      case 'open':
        onRoomTap(shellLayout, chat);
        break;
      case 'window':
        onRoomDoubleTap(shellLayout, chat);
        break;
      case 'mute':
        await MutedChatsStore.instance.setMuted(chat.id, true);
        break;
      case 'unmute':
        await MutedChatsStore.instance.setMuted(chat.id, false);
        break;
      default:
        break;
    }
  }

  /// Touch: long-press a room row for mute / unmute (desktop uses the context menu).
  Future<void> showMobileRoomLongPressMenu(
    BuildContext context,
    Chat chat,
  ) async {
    await MutedChatsStore.instance.ensureLoaded();
    if (!context.mounted) return;
    final muted = MutedChatsStore.instance.isMuted(chat.id);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  muted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                ),
                title: Text(muted ? 'Unmute chat' : 'Mute chat'),
                subtitle: Text(
                  muted
                      ? 'Show unread count and notifications again'
                      : 'Hide unread badge and notifications for this room',
                  style: theme.textTheme.bodySmall,
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await MutedChatsStore.instance.setMuted(chat.id, !muted);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void onChatTypeSelected(ChatType t) => selectedChatType.value = t;

  Future<void> createRoom() async {
    if (!context.read<NetworkAvailability>().isOnline) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connect to the internet to create a room.'),
          ),
        );
      }
      return;
    }
    final result = await openCreateChat(context);
    if (result != null) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final currentState = chatState.value;
      if (currentState is ChatStateLoaded && context.mounted) {
        final room = currentState.rooms.firstWhere(
          (e) => e.id == result,
          orElse: () => Chat(
            id: '',
            name: '',
            lastMessage: '',
            status: ChatRoomStatus.invited,
          ),
        );
        if (room.id.isNotEmpty) {
          _actionsFor(_variant(context)).openRoom(context, room);
        }
      }
    }
  }

  void openSettings() => unawaited(openSettingsFrom(context));

  void openCallHistory() {
    if (!isDesktopTargetPlatform()) {
      mobileHomeTabIndex.value = 1;
      return;
    }
    desktopSidebarTabIndex.value = 1;
  }

  Future<void> refreshRecoveryBannerState() async {
    try {
      final persisted = await KeyRecoveryPrefs.isBannerDontShowAgain();
      recoveryBannerDontShowAgainPersisted.value = persisted;
      await MatrixService().client.refreshRecoveryState();
      final s = await MatrixService().client.getRecoveryState();
      recoveryBannerState.value = s;
      final backup = await MatrixService().client.backupExistsOnServer();
      recoveryServerBackupExists.value = backup;
    } catch (e) {
      LoggingService.error(
        'MESSAGING_WORKSPACE',
        'refreshRecoveryBannerState: $e',
      );
      recoveryBannerState.value = 'unknown';
      recoveryServerBackupExists.value = false;
    }
  }

  void dismissRecoveryBanner(bool dontShowAgain) {
    if (dontShowAgain) {
      unawaited(_applyBannerDontShowAgain(true));
    } else {
      recoveryBannerDismissedThisSession.value = true;
    }
  }

  Future<void> openKeyRecoverySetup(
    BuildContext anchorContext, {
    bool dontShowAgain = false,
  }) async {
    if (dontShowAgain) {
      await _applyBannerDontShowAgain(true);
    }
    if (!anchorContext.mounted) return;
    final Widget page = preferUnlockRecoveryBanner
        ? const LoginRecoveryUnlockScreen(closeWhenDone: true)
        : const SetupKeyRecoveryScreen(showEducation: true);
    final title =
        preferUnlockRecoveryBanner ? 'Unlock encryption' : 'Key backup';
    await openShellFlow<void>(
      anchorContext: anchorContext,
      page: page,
      windowTitle: title,
      preferredWindowSize: const Size(520, 640),
    );
    if (anchorContext.mounted) {
      await refreshRecoveryBannerState();
    }
  }

  void onDesktopCloseOrClear() {
    final nav = nestedNavigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return;
    }
    if (_variant(context) == AppLayoutVariant.split) {
      selectedRoom.value = null;
    }
  }

  Future<void> _loadBannerDontShowAgainFromPrefs() async {
    try {
      if (await KeyRecoveryPrefs.isBannerDontShowAgain()) {
        recoveryBannerDontShowAgainPersisted.value = true;
      }
    } catch (_) {}
  }

  @override
  void initWidgetModel() {
    super.initWidgetModel();
    if (mobileHomeTabIndex.value > 1) {
      mobileHomeTabIndex.value = 0;
    }
    if (desktopSidebarTabIndex.value > 1) {
      desktopSidebarTabIndex.value = 0;
    }
    roomListSearchController = TextEditingController();
    unawaited(TimelineLocalHiddenStore.ensureLoaded());
    unawaited(MutedChatsStore.instance.ensureLoaded());
    unawaited(_loadBannerDontShowAgainFromPrefs());
    unawaited(refreshRecoveryBannerState());
    _loadAllChats();
    _listenToChatUpdates();
    selectedRoom.addListener(_onSelectedRoomForTypingResync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final v = _variant(context);
    if (_lastLayout != v) {
      _onLayoutVariantChanged(_lastLayout, v);
      _lastLayout = v;
    }
  }

  void _onLayoutVariantChanged(AppLayoutVariant? oldV, AppLayoutVariant newV) {
    if (oldV == AppLayoutVariant.split && newV == AppLayoutVariant.compact) {
      final chat = selectedRoom.value;
      if (chat != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final nav = nestedNavigatorKey.currentState;
          if (nav != null && nav.mounted) {
            unawaited(
              nav.push(
                MaterialPageRoute<void>(
                  builder: (c) => ConversationScreen(
                    roomId: chat.id,
                    roomName: chat.name,
                    status: chat.status,
                  ),
                ),
              ),
            );
          }
        });
      }
    }
    if (oldV == AppLayoutVariant.compact && newV == AppLayoutVariant.split) {
      final nav = nestedNavigatorKey.currentState;
      if (nav != null && nav.canPop()) {
        nav.popUntil((r) => r.isFirst);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && _isSubscribed) {
      LoggingService.info(
        'MESSAGING_WORKSPACE',
        'App resumed, restarting sync to restore room updates',
      );
      unawaited(_restartSyncAndResubscribe());
      unawaited(refreshRecoveryBannerState());
      unawaited(ProfileLocalCache.refreshFromClient(MatrixService().client));
      unawaited(ProfilePrefs.instance.refresh(MatrixService().client));
    }
  }

  @override
  void dispose() {
    _emptyRoomListSettleTimer?.cancel();
    _isSubscribed = false;
    MatrixService().clearRoomTypingSubscriptions();
    MatrixService().unregisterRoomUpdatesSubscription();
    _roomListSubscription?.cancel();
    _roomListSubscription = null;
    _reconnectionTimer?.cancel();
    _stopHealthCheck();
    roomListKeyboardFocusId.dispose();
    roomListFocusNode.dispose();
    roomListSearchController.dispose();
    mobileHomeTabIndex.dispose();
    desktopSidebarTabIndex.dispose();
    chatState.dispose();
    selectedChatType.dispose();
    selectedRoom.dispose();
    recoveryBannerState.dispose();
    recoveryBannerDismissedThisSession.dispose();
    recoveryBannerDontShowAgainPersisted.dispose();
    recoveryServerBackupExists.dispose();
    selectedRoom.removeListener(_onSelectedRoomForTypingResync);
    super.dispose();
  }

  Future<void> _loadAllChats() async {
    chatState.value = const ChatState.loading();
    _listenToChatUpdates();
  }

  void _syncTypingSubscriptionsForRooms(List<Chat> chats) {
    final joined = chats
        .where((c) => c.status == ChatRoomStatus.joined)
        .toList(growable: false);
    joined.sort((a, b) {
      final ta = a.lastActivity?.millisecondsSinceEpoch ?? 0;
      final tb = b.lastActivity?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta);
    });
    final sel = selectedRoom.value?.id;
    final ordered = <String>[];
    if (sel != null &&
        sel.isNotEmpty &&
        joined.any((c) => c.id == sel)) {
      ordered.add(sel);
    }
    for (final c in joined) {
      if (c.id != sel) ordered.add(c.id);
    }
    MatrixService().syncRoomTypingSubscriptions(ordered);
  }

  void _onRoomList(List<Chat> list) {
    LoggingService.info(
      'MESSAGING_WORKSPACE',
      'Received room list: ${list.length} rooms',
    );
    _emptyRoomListSettleTimer?.cancel();

    if (list.isEmpty) {
      MatrixService().syncRoomTypingSubscriptions(const []);
      final hadRooms = chatState.value.maybeWhen(
        loaded: (rooms) => rooms.isNotEmpty,
        orElse: () => false,
      );
      if (hadRooms) {
        chatState.value = const ChatState.loaded(rooms: []);
        selectedChatType.value = selectedChatType.value;
        _lastUpdateTime = DateTime.now();
        return;
      }
      chatState.value = const ChatState.loading();
      _emptyRoomListSettleTimer = Timer(_emptyListSettleDuration, () {
        if (!_isSubscribed || !context.mounted) return;
        MatrixService().syncRoomTypingSubscriptions(const []);
        chatState.value = const ChatState.loaded(rooms: []);
        selectedChatType.value = selectedChatType.value;
      });
      _lastUpdateTime = DateTime.now();
      return;
    }

    chatState.value = ChatState.loaded(rooms: list);
    selectedChatType.value = selectedChatType.value;
    _lastUpdateTime = DateTime.now();
    _syncTypingSubscriptionsForRooms(list);
  }

  void _listenToChatUpdates() {
    _roomListSubscription?.cancel();

    _roomListSubscription = model.subscribeToRoomList().listen(
      _onRoomList,
      onError: (Object error) {
        LoggingService.error(
          'MESSAGING_WORKSPACE',
          'Error in room list stream: $error',
        );
        _scheduleReconnection();
      },
      onDone: () {
        LoggingService.info(
          'MESSAGING_WORKSPACE',
          'Room list stream completed',
        );
        if (_isSubscribed) {
          _scheduleReconnection();
        }
      },
    );

    MatrixService().registerRoomUpdatesSubscription(_roomListSubscription!);
    _isSubscribed = true;
    _resetReconnectionAttempts();
    _startHealthCheck();
    LoggingService.info(
      'MESSAGING_WORKSPACE',
      'Started listening to room list',
    );
  }

  void retry() => _loadAllChats();

  Future<Uint8List?> loadListingThumbnail(String roomId, Message message) =>
      model.loadListingThumbnail(roomId, message);

  Future<Uint8List?> loadRoomAvatarThumbnail(String mxcUri) =>
      model.loadRoomAvatarThumbnail(mxcUri);

  Future<void> _restartSyncAndResubscribe() async {
    try {
      await MatrixService().client.restartSyncService();
      if (_isSubscribed) _listenToChatUpdates();
    } catch (e) {
      LoggingService.error('MESSAGING_WORKSPACE', 'Failed to restart sync: $e');
      if (_isSubscribed) _scheduleReconnection();
    }
  }

  void _scheduleReconnection() {
    if (!_isSubscribed) return;
    _reconnectionTimer?.cancel();
    final delay = Duration(
      seconds:
          (_initialReconnectionDelay.inSeconds * (1 << _reconnectionAttempts))
              .clamp(1, _maxReconnectionDelay.inSeconds),
    );
    _reconnectionTimer = Timer(delay, () {
      if (_isSubscribed && _reconnectionAttempts < _maxReconnectionAttempts) {
        _reconnectionAttempts++;
        unawaited(_restartSyncAndResubscribe());
      } else if (_reconnectionAttempts >= _maxReconnectionAttempts) {
        _reconnectionAttempts = 0;
      }
    });
  }

  void _resetReconnectionAttempts() {
    if (_reconnectionAttempts > 0) {
      _reconnectionAttempts = 0;
    }
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (timer) {
      if (!_isSubscribed) {
        timer.cancel();
        return;
      }
      if (_lastUpdateTime != null) {
        final timeSinceLastUpdate = DateTime.now().difference(_lastUpdateTime!);
        if (timeSinceLastUpdate > _healthCheckInterval) {
          _scheduleReconnection();
        }
      }
    });
  }

  void _stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }
}
