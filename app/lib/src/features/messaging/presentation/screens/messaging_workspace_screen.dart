import 'dart:async';

import 'package:elementary/elementary.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/src/core/desktop/desktop_resizable_split_pane.dart';
import 'package:matrix/src/core/desktop/desktop_shortcuts.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/desktop/desktop_shell_scope.dart';
import 'package:matrix/src/core/layout/app_layout_scope.dart';
import 'package:matrix/src/core/layout/app_layout_variant.dart';
import 'package:matrix/src/core/layout/messaging_layout_preference.dart';
import 'package:matrix/src/core/network/network_availability.dart';
import 'package:matrix/src/core/calls/native_livekit_call_banner.dart';
import 'package:matrix/src/core/calls/native_livekit_call_host.dart';
import 'package:matrix/src/features/calls/presentation/screens/call_history_screen.dart';
import 'package:provider/provider.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/core/timeline_local_hidden_store.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/features/chat_lisitng/routes/chat_listing_routes.dart';
import 'package:matrix/src/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:matrix/src/features/create_chat/presentation/screens/create_chat_screen.dart';
import 'package:matrix/src/features/messaging/domain/messaging_room_list_model.dart';
import 'package:matrix/src/features/messaging/presentation/screens/messaging_workspace_wm.dart';
import 'package:matrix/src/features/key_recovery/presentation/widgets/key_recovery_banner.dart';
import 'package:matrix/src/features/messaging/presentation/widgets/chat_list_pane.dart';
import 'package:matrix/src/features/settings/presentation/screens/settings_screen.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';

MessagingWorkspaceWM messagingWorkspaceWMFactory(BuildContext context) {
  return MessagingWorkspaceWM(MessagingRoomListModel(MatrixService()));
}

/// Logical size when [MediaQuery.size] is missing or invalid (edge cases).
Size _messagingShellFallbackViewSize() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return const Size(1024, 768);
  final v = views.first;
  final dpr = v.devicePixelRatio;
  if (dpr <= 0) return const Size(1024, 768);
  return Size(
    v.physicalSize.width / dpr,
    v.physicalSize.height / dpr,
  );
}

class MessagingWorkspaceScreen extends ElementaryWidget<MessagingWorkspaceWM>
    implements ChatListingRoutes {
  const MessagingWorkspaceScreen({super.key})
    : super(messagingWorkspaceWMFactory);

  @override
  Widget build(MessagingWorkspaceWM wm) {
    return _MessagingWorkspaceLayoutShell(wm: wm);
  }

  @override
  void navigateToConversationScreen(
    BuildContext context,
    String chatId,
    String roomName,
    ChatRoomStatus status,
  ) {
    final nested = DesktopShellScope.maybeOf(context)?.nestedShellNavigator;
    final page = ConversationScreen(
      roomId: chatId,
      roomName: roomName,
      status: status,
    );
    if (nested != null && nested.mounted) {
      unawaited(
        nested.push<void>(
          MaterialPageRoute<void>(builder: (c) => page),
        ),
      );
      return;
    }
    NavigatorService.push(context, page);
  }

  @override
  Future<String?> navigateToCreateScreen(BuildContext context) {
    return NavigatorService.push<String?>(context, const CreateChatScreen());
  }

  @override
  void navigateToSettingsScreen(BuildContext context) {
    NavigatorService.push(context, const SettingsScreen());
  }
}

/// Gives the shell a finite size when ancestors pass unbounded constraints
/// (e.g. route transitions). Uses [MediaQuery] only in normal [build], not
/// inside [LayoutBuilder], so laying out the subtree cannot re-enter layout.
class _MessagingWorkspaceLayoutShell extends StatelessWidget {
  const _MessagingWorkspaceLayoutShell({required this.wm});

  final MessagingWorkspaceWM wm;

  @override
  Widget build(BuildContext context) {
    final layoutPref = context.watch<MessagingLayoutPreferenceNotifier>().value;
    final mq = MediaQuery.of(context);
    final variant = resolveMessagingLayoutVariant(
      mq: mq,
      preference: layoutPref,
    );

    Widget shell = DesktopShellScope(
      launcher: wm,
      child: AppLayoutScope(
        variant: variant,
        child: _MessagingBody(variant: variant, wm: wm),
      ),
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      shell = PlatformMenuBar(
        menus: [
          PlatformMenu(
            label: 'File',
            menus: [
              PlatformMenuItem(
                label: 'New Room…',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyN,
                  meta: true,
                ),
                onSelected: () => unawaited(wm.createRoom()),
              ),
            ],
          ),
          PlatformMenu(
            label: 'View',
            menus: [
              PlatformMenuItem(
                label: 'Settings…',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.comma,
                  meta: true,
                ),
                onSelected: wm.openSettings,
              ),
              PlatformMenuItem(
                label: 'Close or Go Back',
                shortcut: const SingleActivator(LogicalKeyboardKey.escape),
                onSelected: wm.onDesktopCloseOrClear,
              ),
            ],
          ),
          PlatformMenu(
            label: 'Help',
            menus: [
              PlatformMenuItem(
                label: 'Keyboard Shortcuts…',
                onSelected: () => unawaited(
                  MessagingDesktopShortcuts.showShortcutsReferenceDialog(
                    context,
                  ),
                ),
              ),
            ],
          ),
        ],
        child: shell,
      );
    }

    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows)) {
      shell = MessagingDesktopShortcuts(
        onNewChat: wm.createRoom,
        onOpenSettings: wm.openSettings,
        onCloseOrClear: wm.onDesktopCloseOrClear,
        child: shell,
      );
    }

    final viewSize = mq.size;
    final fb = _messagingShellFallbackViewSize();
    final w = viewSize.width.isFinite && viewSize.width > 0
        ? viewSize.width
        : fb.width;
    final h = viewSize.height.isFinite && viewSize.height > 0
        ? viewSize.height
        : fb.height;
    return SizedBox(width: w, height: h, child: shell);
  }
}

class _MessagingBody extends StatelessWidget {
  const _MessagingBody({required this.variant, required this.wm});

  final AppLayoutVariant variant;
  final MessagingWorkspaceWM wm;

  @override
  Widget build(BuildContext context) {
    return variant == AppLayoutVariant.split
        ? _splitBody(context)
        : _compactBody(context);
  }

  /// Shell actions shared by split sidebar bar and compact list route.
  List<Widget> _workspaceAppBarActions(BuildContext context) {
    final desktop = isDesktopTargetPlatform();
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return [
      IconButton(
        icon: const Icon(Icons.add),
        onPressed: wm.createRoom,
        tooltip: desktop
            ? (apple ? 'New room (⌘N)' : 'New room (Ctrl+N)')
            : 'Create Room',
      ),
      if (desktop)
        IconButton(
          icon: const Icon(Icons.history),
          onPressed: wm.openCallHistory,
          tooltip: 'Call history',
        ),
      IconButton(
        icon: const Icon(Icons.settings),
        onPressed: wm.openSettings,
        tooltip: desktop
            ? (apple ? 'Settings (⌘,)' : 'Settings (Ctrl+,)')
            : 'Settings',
      ),
    ];
  }

  /// Same title styling as [TerminalScreen] for the workspace shell.
  Widget _workspaceAppBarTitle(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final desktop = isDesktopTargetPlatform();
    final title = desktop ? 'Matrix' : 'MATRIX';
    if (desktop) {
      return Text(
        title,
        style: theme.appBarTheme.titleTextStyle?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.92),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text(
      title,
      style: MatrixTheme.subtitleStyle.copyWith(
        color: MatrixTheme.matrixLightGreen,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 3,
        shadows: [
          Shadow(
            color: MatrixTheme.matrixGreen.withValues(alpha: 0.55),
            blurRadius: 12,
          ),
          Shadow(
            color: MatrixTheme.matrixAccent.withValues(alpha: 0.35),
            blurRadius: 18,
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  PreferredSizeWidget _workspaceAppBar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final desktop = isDesktopTargetPlatform();
    return AppBar(
      automaticallyImplyLeading: false,
      title: _workspaceAppBarTitle(context),
      actions: _workspaceAppBarActions(context),
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: theme.scaffoldBackgroundColor,
      foregroundColor: desktop ? scheme.onSurface : MatrixTheme.matrixGreen,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(
        color: desktop ? scheme.onSurface : MatrixTheme.matrixGreen,
      ),
      actionsIconTheme: IconThemeData(
        color: desktop ? scheme.onSurface : MatrixTheme.matrixGreen,
      ),
      bottom: desktop
          ? PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            )
          : null,
    );
  }

  Widget _compactBody(BuildContext context) {
    final nestedNav = Navigator(
      key: wm.nestedNavigatorKey,
      onGenerateInitialRoutes: (navigator, initialRoute) {
        return [
          MaterialPageRoute<void>(
            builder: (ctx) {
              if (isDesktopTargetPlatform()) {
                return TerminalScreen(
                  title: 'Matrix',
                  actions: _workspaceAppBarActions(ctx),
                  child: ListenableBuilder(
                    listenable: wm.desktopSidebarTabIndex,
                    builder: (context, _) {
                      final tab = wm.desktopSidebarTabIndex.value.clamp(0, 1);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DesktopMessengerTabs(
                            selectedIndex: tab,
                            onDestinationSelected: (i) =>
                                wm.desktopSidebarTabIndex.value = i,
                          ),
                          Expanded(
                            child: tab == 1
                                ? const CallHistoryScreen(
                                    embedInParentScaffold: true,
                                  )
                                : _chatListScaffold(ctx, variant),
                          ),
                        ],
                      );
                    },
                  ),
                );
              }
              return _buildCompactPhoneHome(ctx);
            },
            settings: RouteSettings(name: initialRoute),
          ),
        ];
      },
    );

    // Android: system back must pop the inner stack (conversation → home) before
    // finishing the activity; otherwise the root route can receive pop + app exit.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          final nav = wm.nestedNavigatorKey.currentState;
          if (nav != null && nav.canPop()) {
            nav.pop();
            return;
          }
          SystemNavigator.pop();
        },
        child: nestedNav,
      );
    }

    return nestedNav;
  }

  /// Phone / tablet home: chats + calls with a bottom [NavigationBar].
  Widget _buildCompactPhoneHome(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        wm.mobileHomeTabIndex,
        NativeLiveKitCallHost.instance,
      ]),
      builder: (context, _) {
        final tab = wm.mobileHomeTabIndex.value;
        final host = NativeLiveKitCallHost.instance;
        final session = host.session;
        final callBottom = (host.showInAppOngoingCallStrip && session != null)
            ? NativeLiveKitMinimizedCallAppBarBottom(
                session: session,
                onOpen: () =>
                    unawaited(openNativeLiveKitCallUiFromBanner(context)),
                onHangUp: () => unawaited(session.hangUp()),
              )
            : null;
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: tab == 0
                ? _workspaceAppBarTitle(context)
                : Text(
                    'CALLS',
                    style: MatrixTheme.subtitleStyle.copyWith(
                      color: MatrixTheme.matrixLightGreen,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      shadows: [
                        Shadow(
                          color: MatrixTheme.matrixGreen.withValues(
                            alpha: 0.55,
                          ),
                          blurRadius: 12,
                        ),
                        Shadow(
                          color: MatrixTheme.matrixAccent.withValues(
                            alpha: 0.35,
                          ),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                  ),
            actions: _workspaceAppBarActions(context),
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: theme.scaffoldBackgroundColor,
            foregroundColor: MatrixTheme.matrixGreen,
            surfaceTintColor: Colors.transparent,
            iconTheme: IconThemeData(color: MatrixTheme.matrixGreen),
            actionsIconTheme: IconThemeData(color: MatrixTheme.matrixGreen),
            bottom: callBottom,
          ),
          body: IndexedStack(
            index: tab,
            children: [
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: MatrixTheme.backgroundGradient,
                ),
                child: SafeArea(child: _chatListScaffold(context, variant)),
              ),
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: MatrixTheme.backgroundGradient,
                ),
                child: const SafeArea(
                  child: CallHistoryScreen(embedInParentScaffold: true),
                ),
              ),
            ],
          ),
          bottomNavigationBar: _MatrixTerminalBottomNav(
            selectedIndex: tab,
            onDestinationSelected: (i) => wm.mobileHomeTabIndex.value = i,
          ),
        );
      },
    );
  }

  Widget _splitBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DesktopResizableSplitPane(
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.55),
      sidebar: Material(
        color: scheme.surfaceContainerLow,
        child: Scaffold(
          backgroundColor: scheme.surfaceContainerLow,
          appBar: _workspaceAppBar(context),
          body: ListenableBuilder(
            listenable: wm.desktopSidebarTabIndex,
            builder: (context, _) {
              final tab = wm.desktopSidebarTabIndex.value.clamp(0, 1);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DesktopMessengerTabs(
                    selectedIndex: tab,
                    onDestinationSelected: (i) =>
                        wm.desktopSidebarTabIndex.value = i,
                  ),
                  Expanded(
                    child: tab == 1
                        ? const CallHistoryScreen(
                            embedInParentScaffold: true,
                          )
                        : _chatListScaffold(context, variant),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      detail: Material(color: scheme.surface, child: _splitDetail(context)),
    );
  }

  Widget _chatListScaffold(BuildContext context, AppLayoutVariant shellLayout) {
    final net = context.watch<NetworkAvailability>();
    return ListenableBuilder(
      listenable: Listenable.merge([
        net,
        wm.chatState,
        wm.selectedChatType,
        wm.selectedRoom,
        wm.roomListKeyboardFocusId,
        wm.recoveryBannerState,
        wm.recoveryBannerDismissedThisSession,
        wm.recoveryBannerDontShowAgainPersisted,
        wm.recoveryServerBackupExists,
        TimelineLocalHiddenStore.revision,
        MatrixService().roomListTypingUserIds,
        wm.roomListSearchController,
      ]),
      builder: (context, _) {
        final state = wm.chatState.value;
        return state.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (message) => _listError(context, message),
          loaded: (rooms) {
            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            final searchQ = wm.roomListSearchController.text;
            if (isDesktopTargetPlatform()) {
              final filtered = filterChatsBySearchQuery(
                orderedChatsForListing(rooms, wm.selectedChatType.value),
                searchQ,
              );
              final fid = wm.roomListKeyboardFocusId.value;
              if (fid != null && !filtered.any((c) => c.id == fid)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  wm.roomListKeyboardFocusId.value = null;
                });
              }
            }
            final pane = ChatListPane(
              rooms: rooms,
              typingByRoomId: MatrixService().roomListTypingUserIds.value,
              selectedChatType: wm.selectedChatType.value,
              selectedRoomId: shellLayout == AppLayoutVariant.split
                  ? wm.selectedRoom.value?.id
                  : null,
              searchQuery: searchQ,
              onChatTypeSelected: wm.onChatTypeSelected,
              onRoomTap: (c) => wm.onRoomTap(shellLayout, c),
              onRoomDoubleTap: (c) => wm.onRoomDoubleTap(shellLayout, c),
              loadListingThumbnail: wm.loadListingThumbnail,
              loadRoomAvatarThumbnail: wm.loadRoomAvatarThumbnail,
              onStartChatPressed: wm.createRoom,
              onRoomSecondaryPointer: isDesktopTargetPlatform()
                  ? (c, pos) => unawaited(
                      wm.showRoomListContextMenu(context, shellLayout, c, pos),
                    )
                  : null,
              onRoomMiddleClick: isDesktopTargetPlatform()
                  ? (c) => wm.onRoomDoubleTap(shellLayout, c)
                  : null,
              listFocusNode: isDesktopTargetPlatform()
                  ? wm.roomListFocusNode
                  : null,
              keyboardFocusedRoomId: isDesktopTargetPlatform()
                  ? wm.roomListKeyboardFocusId
                  : null,
              onRoomLongPress: isDesktopTargetPlatform()
                  ? null
                  : (c) =>
                        unawaited(wm.showMobileRoomLongPressMenu(context, c)),
            );
            final list = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isDesktopTargetPlatform() ? 12 : 14,
                    10,
                    isDesktopTargetPlatform() ? 12 : 14,
                    6,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: TextField(
                      controller: wm.roomListSearchController,
                      textInputAction: TextInputAction.search,
                      style: MatrixTheme.inputStyle.copyWith(
                        fontSize: isDesktopTargetPlatform() ? 14 : 13,
                        color: scheme.onSurface.withValues(alpha: 0.95),
                      ),
                      cursorColor: MatrixTheme.matrixAccent,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: MatrixTheme.terminalBlack.withValues(
                          alpha: isDesktopTargetPlatform() ? 0.35 : 0.5,
                        ),
                        hintText: '> SCAN_ROOM_INDEX…',
                        hintStyle: MatrixTheme.hintStyle.copyWith(
                          fontSize: 13,
                          color: MatrixTheme.matrixDarkGreen.withValues(
                            alpha: 0.75,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.terminal,
                          size: 20,
                          color: MatrixTheme.matrixAccent.withValues(
                            alpha: 0.85,
                          ),
                        ),
                        suffixIcon: searchQ.trim().isNotEmpty
                            ? IconButton(
                                tooltip: 'Clear',
                                icon: Icon(
                                  Icons.backspace_outlined,
                                  size: 20,
                                  color: MatrixTheme.matrixLightGreen
                                      .withValues(alpha: 0.9),
                                ),
                                onPressed: wm.roomListSearchController.clear,
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(
                            color: MatrixTheme.terminalBorder.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(
                            color: MatrixTheme.matrixGreen.withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(
                            color: MatrixTheme.matrixAccent.withValues(
                              alpha: 0.95,
                            ),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!net.isOnline)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isDesktopTargetPlatform() ? 12 : 14,
                      0,
                      isDesktopTargetPlatform() ? 12 : 14,
                      8,
                    ),
                    child: Material(
                      color: scheme.errorContainer.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.wifi_off,
                              size: 20,
                              color: scheme.onErrorContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Offline — your chats are local. Sending messages, calls, and new rooms need internet.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onErrorContainer,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(child: pane),
              ],
            );
            if (!wm.shouldShowRecoveryBanner) {
              return list;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyRecoveryBanner(
                  preferUnlockFlow: wm.preferUnlockRecoveryBanner,
                  onSetUp: (dontShowAgain) => unawaited(
                    wm.openKeyRecoverySetup(
                      context,
                      dontShowAgain: dontShowAgain,
                    ),
                  ),
                  onDismiss: wm.dismissRecoveryBanner,
                ),
                Expanded(child: list),
              ],
            );
          },
        );
      },
    );
  }

  Widget _listError(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Center(
      child: TerminalContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
            const SizedBox(height: 16),
            Text(
              'ERROR',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TerminalButton(
              text: 'RETRY',
              onPressed: wm.retry,
              icon: Icons.refresh,
            ),
          ],
        ),
      ),
    );
  }

  Widget _splitDetail(BuildContext context) {
    return ValueListenableBuilder<Chat?>(
      valueListenable: wm.selectedRoom,
      builder: (context, chat, _) {
        if (chat == null) {
          final theme = Theme.of(context);
          return Center(
            child: Text('SELECT A CHAT', style: theme.textTheme.titleMedium),
          );
        }
        return ConversationScreen(
          key: ValueKey<String>(chat.id),
          roomId: chat.id,
          roomName: chat.name,
          status: chat.status,
          implyLeading: false,
        );
      },
    );
  }
}

/// CHATS / CALLS strip under the desktop sidebar [AppBar] (split layout) or inside
/// [TerminalScreen] (narrow desktop). Matches [_MatrixTerminalBottomNav] styling.
class _DesktopMessengerTabs extends StatelessWidget {
  const _DesktopMessengerTabs({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomLine = MatrixTheme.matrixGreen.withValues(alpha: 0.5);
    return Material(
      color: MatrixTheme.terminalBlack,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border(
            bottom: BorderSide(color: bottomLine, width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: _TerminalNavEntry(
                  label: 'CHATS',
                  selected: selectedIndex == 0,
                  onTap: () => onDestinationSelected(0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TerminalNavEntry(
                  label: 'CALLS',
                  selected: selectedIndex == 1,
                  onTap: () => onDestinationSelected(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Material [NavigationBar] replacement: monospace labels, square borders, no pill indicator.
class _MatrixTerminalBottomNav extends StatelessWidget {
  const _MatrixTerminalBottomNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final topLine = MatrixTheme.matrixGreen.withValues(alpha: 0.5);
    return Material(
      color: MatrixTheme.terminalBlack,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MatrixTheme.terminalBackground.withValues(alpha: 0.98),
            border: Border(top: BorderSide(color: topLine, width: 1)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: _TerminalNavEntry(
                    label: 'CHATS',
                    selected: selectedIndex == 0,
                    onTap: () => onDestinationSelected(0),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TerminalNavEntry(
                    label: 'CALLS',
                    selected: selectedIndex == 1,
                    onTap: () => onDestinationSelected(1),
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

class _TerminalNavEntry extends StatelessWidget {
  const _TerminalNavEntry({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? MatrixTheme.matrixLightGreen
        : MatrixTheme.matrixDarkGreen.withValues(alpha: 0.78);
    final edge = selected
        ? MatrixTheme.matrixGreen
        : MatrixTheme.terminalBorder.withValues(alpha: 0.5);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            border: Border.all(color: edge, width: 1),
            color: selected
                ? MatrixTheme.matrixGreen.withValues(alpha: 0.1)
                : Colors.transparent,
          ),
          child: Text(
            selected ? '> $label' : '  $label',
            textAlign: TextAlign.center,
            style: MatrixTheme.captionStyle.copyWith(
              fontSize: 11,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
