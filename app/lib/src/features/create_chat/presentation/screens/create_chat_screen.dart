import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/features/create_chat/domain/models/create_chat_type.dart';
import 'package:matrix/src/features/create_chat/presentation/screens/create_chat_screen_wm.dart';
import 'package:matrix/src/features/create_chat/presentation/widgets/chat_creation_button.dart';
import 'package:matrix/src/features/create_chat/presentation/widgets/user_tile.dart';
import 'package:matrix/src/features/create_chat/routes/create_chat_routes.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';

CreateChatScreenWM createChatScreenWMFactory(BuildContext context) {
  return CreateChatScreenWM(
    CreateChatScreenModel(matrixService: MatrixService()),
  );
}

class CreateChatScreen extends ElementaryWidget<CreateChatScreenWM>
    implements CreateChatRoutes {
  const CreateChatScreen({super.key}) : super(createChatScreenWMFactory);

  @override
  Widget build(CreateChatScreenWM wm) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            title: Text('CREATE ROOM', style: theme.textTheme.titleLarge),
            elevation: 0,
          ),
          body: Container(
            decoration: BoxDecoration(gradient: wm.backgroundGradient),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ROOM TYPE', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    ValueListenableBuilder(
                      valueListenable: wm.selectedChatType,
                      builder: (context, value, child) {
                        return Row(
                          children: [
                            Expanded(
                              child: ChatCreationButton(
                                type: CreateChatType.direct,
                                label: 'DIRECT CHAT',
                                icon: Icons.person,
                                onTap: () =>
                                    wm.selectChatType(CreateChatType.direct),
                                isSelected: value == CreateChatType.direct,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ChatCreationButton(
                                type: CreateChatType.group,
                                label: 'GROUP CHAT',
                                icon: Icons.group,
                                isSelected: value == CreateChatType.group,
                                onTap: () =>
                                    wm.selectChatType(CreateChatType.group),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Text('ADD PARTICIPANTS', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    TextField(
                      controller: wm.searchController,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'Search users (@username or username)...',
                        hintStyle: theme.textTheme.bodyMedium,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        suffixIcon: ValueListenableBuilder(
                          valueListenable: wm.isSearching,
                          builder: (context, isSearching, child) {
                            if (isSearching) {
                              return Padding(
                                padding: const EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              );
                            }
                            return Icon(
                              Icons.search,
                              color: theme.colorScheme.primary,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ValueListenableBuilder(
                      valueListenable: wm.searchResults,
                      builder: (context, searchResults, child) {
                        return Column(
                          children: [
                            Text(
                              'SEARCH RESULTS',
                              style: theme.textTheme.labelLarge,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: ListView.builder(
                                itemCount: searchResults.length,
                                itemBuilder: (context, index) {
                                  final user = searchResults[index];
                                  return UserTile(
                                    user: user,
                                    trailing: IconButton(
                                      icon: Icon(
                                        Icons.add,
                                        color: theme.colorScheme.primary,
                                      ),
                                      onPressed: () => wm.addUser(user),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        );
                      },
                    ),
                    Expanded(
                      child: ValueListenableBuilder(
                        valueListenable: wm.selectedUsers,
                        builder: (context, selectedUsers, child) {
                          if (selectedUsers.isNotEmpty) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SELECTED PARTICIPANTS (${selectedUsers.length})',
                                  style: theme.textTheme.labelLarge,
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: selectedUsers.length,
                                    itemBuilder: (context, index) {
                                      final user = selectedUsers[index];
                                      return UserTile(
                                        user: user,
                                        trailing: IconButton(
                                          icon: Icon(
                                            Icons.remove,
                                            color: theme.colorScheme.error,
                                          ),
                                          onPressed: () => wm.removeUser(user),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          }
                          return Center(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.person_search,
                                    color: theme.colorScheme.primary,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'NO PARTICIPANTS SELECTED',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'SEARCH AND ADD USERS TO CREATE A ROOM',
                                    style: theme.textTheme.bodyMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: wm.createRoom,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                        ),
                        child: ListenableBuilder(
                          listenable: Listenable.merge([
                            wm.isCreating,
                            wm.selectedChatType,
                          ]),
                          builder: (context, child) {
                            final isCreating = wm.isCreating.value;
                            final text =
                                wm.selectedChatType.value == CreateChatType.direct
                                    ? 'CREATE DIRECT CHAT'
                                    : 'CREATE GROUP CHAT';
                            if (isCreating) {
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'CREATING...',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Text(
                              text,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.onPrimary,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void showSnackBar(context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Future<bool?> getGroupName(
    BuildContext context,
    TextEditingController groupNameController,
  ) async {
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.primary),
        ),
        title: Text('Enter Group Name', style: theme.textTheme.titleLarge),
        content: TextField(
          controller: groupNameController,
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  void goBack(BuildContext context, String chatId) {
    Navigator.of(context).pop(chatId);
  }
}
