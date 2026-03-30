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

class MessagingWorkspaceScreen extends ElementaryWidget<MessagingWorkspaceWM>
    implements ChatListingRoutes {
  const MessagingWorkspaceScreen({super.key})
    : super(messagingWorkspaceWMFactory);

  @override
  Widget build(MessagingWorkspaceWM wm) {
    return LayoutBuilder(
      builder: (context, constraints) {
        context.watch<MessagingLayoutPreferenceNotifier>();
        final mq = MediaQuery.of(context);
        final layoutPref = context
            .read<MessagingLayoutPreferenceNotifier>()
            .value;
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
                    shortcut: const SingleActivator(
                      LogicalKeyboardKey.escape,
                    ),
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

        return shell;
      },
    );
  }

  @override
  void navigateToConversationScreen(
    BuildContext context,
    String chatId,
    String roomName,
    ChatRoomStatus status,
  ) {
    NavigatorService.push(
      context,
      ConversationScreen(roomId: chatId, roomName: roomName, status: status),
    );
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
    return Navigator(
      key: wm.nestedNavigatorKey,
      onGenerateInitialRoutes: (navigator, initialRoute) {
        return [
          MaterialPageRoute<void>(
            builder: (ctx) => TerminalScreen(
              title: isDesktopTargetPlatform() ? 'Matrix' : 'MATRIX',
              actions: _workspaceAppBarActions(ctx),
              child: _chatListScaffold(ctx, variant),
            ),
            settings: RouteSettings(name: initialRoute),
          ),
        ];
      },
    );
  }

  Widget _splitBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DesktopResizableSplitPane(
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.55),
      sidebar: Material(
        color: scheme.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _workspaceAppBar(context),
            Expanded(child: _chatListScaffold(context, variant)),
          ],
        ),
      ),
      detail: Material(color: scheme.surface, child: _splitDetail(context)),
    );
  }

  Widget _chatListScaffold(BuildContext context, AppLayoutVariant shellLayout) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        wm.chatState,
        wm.selectedChatType,
        wm.selectedRoom,
        wm.roomListKeyboardFocusId,
        wm.recoveryBannerState,
        wm.recoveryBannerDismissedThisSession,
        wm.recoveryBannerDontShowAgainPersisted,
        wm.recoveryServerBackupExists,
        TimelineLocalHiddenStore.revision,
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
            if (isDesktopTargetPlatform()) {
              final filtered = filteredChatsForListing(
                rooms,
                wm.selectedChatType.value,
              );
              final fid = wm.roomListKeyboardFocusId.value;
              if (fid != null && !filtered.any((c) => c.id == fid)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  wm.roomListKeyboardFocusId.value = null;
                });
              }
            }
            final list = ChatListPane(
              rooms: rooms,
              selectedChatType: wm.selectedChatType.value,
              selectedRoomId: shellLayout == AppLayoutVariant.split
                  ? wm.selectedRoom.value?.id
                  : null,
              onChatTypeSelected: wm.onChatTypeSelected,
              onRoomTap: (c) => wm.onRoomTap(shellLayout, c),
              onRoomDoubleTap: (c) => wm.onRoomDoubleTap(shellLayout, c),
              loadListingThumbnail: wm.loadListingThumbnail,
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
                    wm.openKeyRecoverySetup(context, dontShowAgain: dontShowAgain),
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
