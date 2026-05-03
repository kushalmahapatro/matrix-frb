import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/features/create_chat/domain/models/create_chat_type.dart';
import 'package:matrix/src/features/create_chat/presentation/screens/create_chat_screen_wm.dart';
import 'package:matrix/src/features/create_chat/presentation/widgets/user_tile.dart';
import 'package:matrix/src/features/create_chat/routes/create_chat_routes.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix_sdk/matrix_sdk.dart' show User;

CreateChatScreenWM createChatScreenWMFactory(BuildContext context) {
  return CreateChatScreenWM(
    CreateChatScreenModel(matrixService: MatrixService()),
  );
}

class CreateChatScreen extends ElementaryWidget<CreateChatScreenWM>
    implements CreateChatRoutes {
  const CreateChatScreen({super.key}) : super(createChatScreenWMFactory);

  static Listenable _bodyListenable(CreateChatScreenWM wm) {
    return Listenable.merge([
      wm.selectedChatType,
      wm.searchResults,
      wm.selectedUsers,
      wm.isSearching,
      wm.searchController,
    ]);
  }

  @override
  Widget build(CreateChatScreenWM wm) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;

        return Scaffold(
          backgroundColor: cs.surface,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            title: Text(
              'New chat',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            centerTitle: true,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          body: DecoratedBox(
            decoration: BoxDecoration(gradient: wm.backgroundGradient),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: ValueListenableBuilder<CreateChatType>(
                    valueListenable: wm.selectedChatType,
                    builder: (context, type, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type == CreateChatType.direct
                                ? 'Direct message'
                                : 'Group conversation',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            type == CreateChatType.direct
                                ? 'Pick one person. If a DM already exists, we’ll offer to open it.'
                                : 'Name the room, then invite one or more people.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ValueListenableBuilder<CreateChatType>(
                    valueListenable: wm.selectedChatType,
                    builder: (context, type, _) {
                      return _MatrixChatModeToggle(
                        selected: type,
                        onSelect: wm.selectChatType,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<CreateChatType>(
                  valueListenable: wm.selectedChatType,
                  builder: (context, type, _) {
                    if (type != CreateChatType.group) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: wm.groupNameController,
                        style: theme.textTheme.bodyLarge,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Group name',
                          hintText: 'Visible in your room list',
                          labelStyle: TextStyle(
                            color: MatrixTheme.matrixDarkGreen,
                            fontFamily: MatrixTheme.fontFamily,
                          ),
                          filled: true,
                          fillColor: MatrixTheme.terminalBackground
                              .withValues(alpha: 0.9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                            borderSide: BorderSide(
                              color: MatrixTheme.terminalBorder,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                            borderSide: BorderSide(
                              color: MatrixTheme.terminalBorder,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                            borderSide: BorderSide(
                              color: MatrixTheme.matrixGreen,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: wm.searchController,
                    style: theme.textTheme.bodyLarge,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search by name or @user…',
                      hintStyle: TextStyle(
                        color: MatrixTheme.matrixDarkGreen,
                        fontFamily: MatrixTheme.fontFamily,
                      ),
                      filled: true,
                      fillColor: MatrixTheme.terminalBackground
                          .withValues(alpha: 0.9),
                      prefixIcon: Icon(
                        Icons.search,
                        color: MatrixTheme.matrixGreen,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(
                          color: MatrixTheme.terminalBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(
                          color: MatrixTheme.terminalBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(
                          color: MatrixTheme.matrixGreen,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 14,
                      ),
                      suffixIcon: ValueListenableBuilder<bool>(
                        valueListenable: wm.isSearching,
                        builder: (context, searching, _) {
                          if (!searching) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: MatrixTheme.matrixGreen,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder<List<User>>(
                  valueListenable: wm.selectedUsers,
                  builder: (context, selected, _) {
                    if (selected.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: SizedBox(
                        height: 44,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: selected.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final u = selected[i];
                            final label = u.displayName?.trim().isNotEmpty == true
                                ? u.displayName!.trim()
                                : u.userIdDisplay;
                            return Material(
                              color: MatrixTheme.terminalDarkGreen
                                  .withValues(alpha: 0.85),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: MatrixTheme.matrixGreen
                                        .withValues(alpha: 0.55),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: ColoredBox(
                                          color: MatrixTheme.matrixDarkGreen,
                                          child: Center(
                                            child: Text(
                                              label.isNotEmpty
                                                  ? label[0].toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: MatrixTheme.matrixGreen,
                                                fontFamily:
                                                    MatrixTheme.fontFamily,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 148,
                                        ),
                                        child: Text(
                                          label,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                            color: MatrixTheme.matrixLightGreen,
                                            fontFamily: MatrixTheme.fontFamily,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                        icon: Icon(
                                          Icons.close,
                                          size: 18,
                                          color: MatrixTheme.errorRed,
                                        ),
                                        onPressed: () => wm.removeUser(u),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _bodyListenable(wm),
                    builder: (context, _) {
                      final type = wm.selectedChatType.value;
                      final query = wm.searchController.text.trim();
                      final results = wm.searchResults.value;
                      final searching = wm.isSearching.value;

                      if (query.isEmpty) {
                        return _EmptySearchState(type: type);
                      }
                      if (!searching && results.isEmpty) {
                        return _NoResultsState(query: query);
                      }
                      if (searching && results.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: CircularProgressIndicator(
                              color: MatrixTheme.matrixGreen,
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final user = results[index];
                          return UserTile(
                            compact: true,
                            terminalStyle: true,
                            user: user,
                            trailing: _MatrixAddButton(
                              onPressed: () => wm.addUser(user),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Material(
                  elevation: 10,
                  color: cs.surface,
                  shadowColor: Colors.black54,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          wm.isCreating,
                          wm.selectedChatType,
                          wm.selectedUsers,
                          wm.groupNameController,
                        ]),
                        builder: (context, _) {
                          final creating = wm.isCreating.value;
                          final type = wm.selectedChatType.value;
                          final canSubmit = type == CreateChatType.direct
                              ? wm.selectedUsers.value.isNotEmpty
                              : wm.groupNameController.text.trim().isNotEmpty &&
                                    wm.selectedUsers.value.isNotEmpty;

                          final label = type == CreateChatType.direct
                              ? 'Start chat'
                              : 'Create group';

                          return FilledButton(
                            onPressed: creating || !canSubmit
                                ? null
                                : wm.createRoom,
                            style: FilledButton.styleFrom(
                              backgroundColor: canSubmit && !creating
                                  ? MatrixTheme.matrixGreen
                                  : MatrixTheme.matrixDarkGreen,
                              foregroundColor: MatrixTheme.terminalBlack,
                              disabledBackgroundColor:
                                  MatrixTheme.terminalBorder,
                              disabledForegroundColor:
                                  MatrixTheme.matrixDarkGreen,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                            child: creating
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: MatrixTheme.terminalBlack,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Working…',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              color: MatrixTheme.terminalBlack,
                                              fontWeight: FontWeight.w800,
                                              fontFamily: MatrixTheme.fontFamily,
                                            ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    label.toUpperCase(),
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      fontFamily: MatrixTheme.fontFamily,
                                      letterSpacing: 1.2,
                                      color: MatrixTheme.terminalBlack,
                                    ),
                                  ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void showSnackBar(
    BuildContext context,
    String message, {
    CreateChatSnackKind kind = CreateChatSnackKind.error,
  }) {
    showCreateChatSnackBar(
      ScaffoldMessenger.of(context),
      message,
      kind: kind,
    );
  }

  @override
  void goBack(BuildContext context, String chatId) {
    Navigator.of(context).pop(chatId);
  }

  @override
  Future<bool?> showExistingDmDialog(
    BuildContext context, {
    required String otherUserId,
    required String otherUserDisplayLabel,
    required String existingRoomId,
  }) {
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: MatrixTheme.terminalBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(
            color: MatrixTheme.matrixGreen.withValues(alpha: 0.65),
            width: 2,
          ),
        ),
        icon: Icon(
          Icons.forum_rounded,
          size: 40,
          color: MatrixTheme.matrixAccent,
        ),
        title: Text(
          'Already chatting',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: MatrixTheme.matrixGreen,
            fontFamily: MatrixTheme.fontFamily,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You already have a direct room with\n\n$otherUserDisplayLabel',
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.4,
                color: MatrixTheme.matrixLightGreen,
                fontFamily: MatrixTheme.fontFamily,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              otherUserId,
              style: theme.textTheme.bodySmall?.copyWith(
                color: MatrixTheme.matrixDarkGreen,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: MatrixTheme.matrixDarkGreen,
            ),
            child: Text(
              'Stay',
              style: TextStyle(fontFamily: MatrixTheme.fontFamily),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MatrixTheme.matrixGreen,
              foregroundColor: MatrixTheme.terminalBlack,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Open chat',
              style: TextStyle(fontFamily: MatrixTheme.fontFamily),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatrixChatModeToggle extends StatelessWidget {
  const _MatrixChatModeToggle({
    required this.selected,
    required this.onSelect,
  });

  final CreateChatType selected;
  final ValueChanged<CreateChatType> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MatrixModeCell(
            selected: selected == CreateChatType.direct,
            label: 'DIRECT',
            icon: Icons.person,
            onTap: () => onSelect(CreateChatType.direct),
          ),
        ),
        Container(width: 1, color: MatrixTheme.terminalBorder),
        Expanded(
          child: _MatrixModeCell(
            selected: selected == CreateChatType.group,
            label: 'GROUP',
            icon: Icons.group,
            onTap: () => onSelect(CreateChatType.group),
          ),
        ),
      ],
    );
  }
}

class _MatrixModeCell extends StatelessWidget {
  const _MatrixModeCell({
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? MatrixTheme.terminalDarkGreen.withValues(alpha: 0.98)
          : MatrixTheme.terminalBackground.withValues(alpha: 0.88),
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? MatrixTheme.matrixGreen
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? MatrixTheme.matrixGreen
                      : MatrixTheme.matrixDarkGreen,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: MatrixTheme.fontFamily,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 12,
                    letterSpacing: 1,
                    color: selected
                        ? MatrixTheme.matrixLightGreen
                        : MatrixTheme.matrixDarkGreen,
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

class _MatrixAddButton extends StatelessWidget {
  const _MatrixAddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Add',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MatrixTheme.terminalDarkGreen.withValues(alpha: 0.95),
            ),
            child: const Icon(
              Icons.add,
              color: MatrixTheme.matrixGreen,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState({required this.type});
  final CreateChatType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.manage_search,
              size: 56,
              color: MatrixTheme.matrixGreen.withValues(alpha: 0.9),
            ),
            const SizedBox(height: 16),
            Text(
              type == CreateChatType.direct
                  ? 'Find your contact'
                  : 'Find people to invite',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              type == CreateChatType.direct
                  ? 'Type a name or Matrix ID above. Results appear here — tap + to select.'
                  : 'Search the directory, then add everyone you want. Names and IDs both work.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off,
              size: 48,
              color: MatrixTheme.matrixDarkGreen,
            ),
            const SizedBox(height: 12),
            Text(
              'No matches',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Nothing found for “$query”. Try another spelling or full @user:server.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
