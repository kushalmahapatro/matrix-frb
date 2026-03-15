import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/features/create_chat/domain/models/create_chat_type.dart';
import 'package:matrix/src/features/create_chat/presentation/screens/create_chat_screen_wm.dart';
import 'package:matrix/src/features/create_chat/presentation/widgets/chat_creation_button.dart';
import 'package:matrix/src/features/create_chat/presentation/widgets/user_tile.dart';
import 'package:matrix/src/features/create_chat/routes/create_chat_routes.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

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
    return Scaffold(
      backgroundColor: MatrixTheme.colors.background,
      appBar: AppBar(
        title: const Text('CREATE ROOM', style: MatrixTheme.titleStyle),
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
                // Room Type Selection
                const Text('ROOM TYPE', style: MatrixTheme.labelStyle),
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

                // User Search
                const Text('ADD PARTICIPANTS', style: MatrixTheme.labelStyle),
                const SizedBox(height: 8),
                TextField(
                  controller: wm.searchController,
                  style: MatrixTheme.bodyStyle,
                  decoration: InputDecoration(
                    hintText: 'Search users (@username or username)...',
                    hintStyle: MatrixTheme.labelStyle,
                    filled: true,
                    fillColor: Colors.grey[900],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: MatrixTheme.primaryGreen,
                      ),
                    ),
                    suffixIcon: ValueListenableBuilder(
                      valueListenable: wm.isSearching,
                      builder: (context, isSearching, child) {
                        if (isSearching) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: MatrixTheme.primaryGreen,
                              ),
                            ),
                          );
                        } else {
                          return const Icon(
                            Icons.search,
                            color: MatrixTheme.primaryGreen,
                          );
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Search Results
                ValueListenableBuilder(
                  valueListenable: wm.searchResults,
                  builder: (context, searchResults, child) {
                    return Column(
                      children: [
                        const Text(
                          'SEARCH RESULTS',
                          style: MatrixTheme.labelStyle,
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
                                  icon: const Icon(
                                    Icons.add,
                                    color: MatrixTheme.primaryGreen,
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

                // Selected Users
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
                              style: MatrixTheme.labelStyle,
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
                                      icon: const Icon(
                                        Icons.remove,
                                        color: Colors.red,
                                      ),
                                      onPressed: () => wm.removeUser(user),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      } else {
                        return const Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.person_search,
                                  color: MatrixTheme.primaryGreen,
                                  size: 48,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'NO PARTICIPANTS SELECTED',
                                  style: MatrixTheme.titleStyle,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'SEARCH AND ADD USERS TO CREATE A ROOM',
                                  style: MatrixTheme.bodyStyle,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),

                // Create Button
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: wm.createRoom,
                    style: MatrixTheme.primaryButtonStyle,
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
                          return const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'CREATING...',
                                style: MatrixTheme.buttonStyle,
                              ),
                            ],
                          );
                        } else {
                          return Text(text, style: MatrixTheme.buttonStyle);
                        }
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
  }

  @override
  void showSnackBar(context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Future<bool?> getGroupName(
    BuildContext context,
    TextEditingController groupNameController,
  ) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: MatrixTheme.primaryGreen),
        ),
        title: Text('Enter Group Name', style: MatrixTheme.titleStyle),
        content: TextField(controller: groupNameController),
        actions: [
          TextButton(
            style: MatrixTheme.secondaryButtonStyle,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            style: MatrixTheme.primaryButtonStyle,
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
