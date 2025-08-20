import 'package:flutter/material.dart';
import 'package:matrix/src/rust/matrix/rooms.dart';
import 'package:matrix/src/rust/matrix/user_serach.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:provider/provider.dart';

enum CreateRoomType { direct, group }

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  CreateRoomType _selectedType = CreateRoomType.direct;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();
  List<User> _searchResults = [];
  final List<User> _selectedUsers = [];
  bool _isSearching = false;
  bool _isCreating = false;

  @override
  void dispose() {
    _searchController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await searchUsers(query: query.trim());
      if (mounted) {
        setState(() {
          _searchResults = results.users;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SEARCH ERROR: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _addUser(User user) {
    if (!_selectedUsers.any((u) => u.userId == user.userId)) {
      setState(() {
        _selectedUsers.add(user);
        _searchResults = [];
        _searchController.clear();
      });
    }
  }

  void _removeUser(User user) {
    setState(() {
      _selectedUsers.removeWhere((u) => u.userId == user.userId);
    });
  }

  Future<void> _createRoom() async {
    if (_selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SELECT AT LEAST ONE USER'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_selectedType == CreateRoomType.group &&
        _groupNameController.text.trim().isEmpty) {
      // show a dialog asking for the group name
      final result = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              backgroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: MatrixTheme.primaryGreen),
              ),
              title: Text('Enter Group Name', style: MatrixTheme.titleStyle),
              content: TextField(controller: _groupNameController),
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

      if (result != true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PROVIDE A GROUP NAME'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() {
      _isCreating = true;
    });

    try {
      String roomId;

      if (_selectedType == CreateRoomType.direct) {
        // For direct chat, only use the first selected user
        roomId = await createDirectRoom(userId: _selectedUsers.first.userId);
      } else {
        // For group chat, use all selected users
        final userIds = _selectedUsers.map((u) => u.userId).toList();
        roomId = await createGroupRoom(
          name: _groupNameController.text.trim(),
          userIds: userIds,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(roomId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ROOM CREATED: $roomId'),
            backgroundColor: MatrixTheme.primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CREATE ROOM ERROR: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('CREATE ROOM', style: MatrixTheme.titleStyle),
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: context.read<ThemeProvider>().backgroundGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Room Type Selection
                const Text('ROOM TYPE', style: MatrixTheme.labelStyle),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildTypeButton(
                        type: CreateRoomType.direct,
                        label: 'DIRECT CHAT',
                        icon: Icons.person,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTypeButton(
                        type: CreateRoomType.group,
                        label: 'GROUP CHAT',
                        icon: Icons.group,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // User Search
                const Text('ADD PARTICIPANTS', style: MatrixTheme.labelStyle),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
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
                    suffixIcon:
                        _isSearching
                            ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: MatrixTheme.primaryGreen,
                                ),
                              ),
                            )
                            : const Icon(
                              Icons.search,
                              color: MatrixTheme.primaryGreen,
                            ),
                  ),
                  onChanged: _searchUsers,
                ),
                const SizedBox(height: 16),

                // Search Results
                if (_searchResults.isNotEmpty) ...[
                  const Text('SEARCH RESULTS', style: MatrixTheme.labelStyle),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final user = _searchResults[index];
                        return _buildUserTile(
                          user: user,
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.add,
                              color: MatrixTheme.primaryGreen,
                            ),
                            onPressed: () => _addUser(user),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Selected Users
                Expanded(
                  child:
                      _selectedUsers.isNotEmpty
                          ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SELECTED PARTICIPANTS (${_selectedUsers.length})',
                                style: MatrixTheme.labelStyle,
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: _selectedUsers.length,
                                  itemBuilder: (context, index) {
                                    final user = _selectedUsers[index];
                                    return _buildUserTile(
                                      user: user,
                                      trailing: IconButton(
                                        icon: const Icon(
                                          Icons.remove,
                                          color: Colors.red,
                                        ),
                                        onPressed: () => _removeUser(user),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          )
                          : const Center(
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
                          ),
                ),

                // Create Button
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isCreating ? null : _createRoom,
                    style: MatrixTheme.primaryButtonStyle,
                    child:
                        _isCreating
                            ? const Row(
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
                            )
                            : Text(
                              _selectedType == CreateRoomType.direct
                                  ? 'CREATE DIRECT CHAT'
                                  : 'CREATE GROUP CHAT',
                              style: MatrixTheme.buttonStyle,
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

  Widget _buildTypeButton({
    required CreateRoomType type,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _selectedType == type;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedType = type;
          _selectedUsers.clear();
          _searchResults.clear();
          _searchController.clear();
          if (type == CreateRoomType.direct) {
            _groupNameController.clear();
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? MatrixTheme.primaryGreen.withValues(alpha: 0.2)
                  : Colors.grey[900],
          border: Border.all(
            color: isSelected ? MatrixTheme.primaryGreen : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? MatrixTheme.primaryGreen : Colors.grey,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: MatrixTheme.bodyStyle.copyWith(
                color: isSelected ? MatrixTheme.primaryGreen : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserTile({required User user, required Widget trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: MatrixTheme.primaryGreen,
            child: Text(
              user.displayName?.isNotEmpty == true
                  ? user.displayName![0].toUpperCase()
                  : user.userId[1].toUpperCase(),
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName ?? user.userId,
                  style: MatrixTheme.bodyStyle.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (user.displayName != null)
                  Text(user.userId, style: MatrixTheme.labelStyle),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
