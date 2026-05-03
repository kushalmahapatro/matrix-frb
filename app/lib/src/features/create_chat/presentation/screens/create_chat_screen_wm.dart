import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/foundation/change_notifier.dart';
import 'package:flutter/src/painting/gradient.dart';
import 'package:matrix/src/core/state_management/base_state_widget_model.dart';
import 'package:matrix/src/features/create_chat/domain/models/create_chat_type.dart';
import 'package:matrix/src/features/create_chat/presentation/screens/create_chat_screen.dart';
import 'package:matrix/src/features/create_chat/routes/create_chat_routes.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:matrix_sdk/matrix_sdk.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class CreateChatScreenModel extends ElementaryModel {
  CreateChatScreenModel({required MatrixService matrixService})
    : _matrixService = matrixService;
  final MatrixService _matrixService;

  Future<Result<UserSearchResult>> searchUsers({required String query}) async {
    try {
      final result = await _matrixService.client.searchUsers(query: query);
      return Success(result);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  Future<String?> getExistingDmRoomId({required String userId}) async {
    return _matrixService.client.getExistingDmRoomId(userId: userId);
  }

  Future<Result<String>> createDirectRoom({required String userId}) async {
    try {
      final result = await _matrixService.client.createDirectRoom(
        userId: userId,
      );
      return Success(result);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  Future<Result<String>> createGroupRoom({
    required String name,
    required List<String> userIds,
  }) async {
    try {
      final result = await _matrixService.client.createGroupRoom(
        name: name,
        userIds: userIds,
      );
      return Success(result);
    } catch (e) {
      return Failure(Exception(e));
    }
  }
}

class CreateChatScreenWM
    extends BaseWidgetModel<CreateChatScreen, CreateChatScreenModel> {
  CreateChatScreenWM(super.model);

  late final ValueNotifier<CreateChatType> _selectedChatType;
  late final TextEditingController _searchController;
  late final TextEditingController _groupNameController;
  late final ValueNotifier<List<User>> _searchResults;
  late final ValueNotifier<bool> _isSearching;
  late final ValueNotifier<List<User>> _selectedUsers;
  late final ValueNotifier<bool> _isCreating;

  @override
  void initWidgetModel() {
    _selectedChatType = ValueNotifier(CreateChatType.direct);
    _searchController = TextEditingController();
    _groupNameController = TextEditingController();
    _searchResults = ValueNotifier([]);
    _isSearching = ValueNotifier(false);
    _selectedUsers = ValueNotifier([]);
    _isCreating = ValueNotifier(false);

    _searchController.addListener(() {
      _searchUsers(_searchController.text);
    });
    super.initWidgetModel();
  }

  @override
  void dispose() {
    _selectedChatType.dispose();
    _searchController.dispose();
    _groupNameController.dispose();
    _searchResults.dispose();
    _isSearching.dispose();
    _selectedUsers.dispose();
    _isCreating.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      _searchResults.value = [];
      return;
    }

    _isSearching.value = true;
    try {
      final results = await model.searchUsers(query: query.trim());
      results.fold(
        (success) {
          _searchResults.value = success.users;
          _isSearching.value = false;
        },
        (failure) => _isSearching.value = false,
      );
    } catch (e) {
      _isSearching.value = false;
      if (context.mounted) {
        widget.showSnackBar(context, 'Search failed: $e');
      }
    }
  }

  Gradient? get backgroundGradient =>
      context.read<ThemeProvider>().backgroundGradient;

  ValueListenable<CreateChatType> get selectedChatType => _selectedChatType;

  TextEditingController get searchController => _searchController;

  TextEditingController get groupNameController => _groupNameController;

  void selectChatType(CreateChatType type) {
    if (_selectedChatType.value == type) return;
    _selectedChatType.value = type;
    _selectedUsers.value = [];
    _searchResults.value = [];
    _searchController.clear();
    if (type == CreateChatType.direct) {
      _groupNameController.clear();
    }
  }

  ValueListenable<List<User>> get searchResults => _searchResults;

  ValueListenable<bool> get isSearching => _isSearching;
  ValueListenable<List<User>> get selectedUsers => _selectedUsers;

  ValueListenable<bool> get isCreating => _isCreating;

  void addUser(User user) {
    if (_selectedChatType.value == CreateChatType.direct) {
      if (_selectedUsers.value.length == 1 &&
          _selectedUsers.value.first.userId == user.userId) {
        return;
      }
      _selectedUsers.value = [user];
    } else {
      if (_selectedUsers.value.any((u) => u.userId == user.userId)) return;
      _selectedUsers.value = [..._selectedUsers.value, user];
    }
    _searchResults.value = [];
    _searchController.clear();
  }

  void removeUser(User user) {
    final users = _selectedUsers.value;
    users.removeWhere((u) => u.userId == user.userId);
    _selectedUsers.value = users;
  }

  Future<void> createRoom() async {
    if (_selectedChatType.value == CreateChatType.direct) {
      if (_selectedUsers.value.isEmpty) {
        widget.showSnackBar(
          context,
          'Choose someone to message.',
          kind: CreateChatSnackKind.neutral,
        );
        return;
      }
    } else {
      if (_groupNameController.text.trim().isEmpty) {
        widget.showSnackBar(
          context,
          'Add a group name first.',
          kind: CreateChatSnackKind.neutral,
        );
        return;
      }
      if (_selectedUsers.value.isEmpty) {
        widget.showSnackBar(
          context,
          'Invite at least one person.',
          kind: CreateChatSnackKind.neutral,
        );
        return;
      }
    }

    _isCreating.value = true;

    try {
      if (_selectedChatType.value == CreateChatType.direct) {
        final otherUserId = _selectedUsers.value.first.userId;
        final existingRoomId = await model.getExistingDmRoomId(
          userId: otherUserId,
        );
        if (!context.mounted) return;
        if (existingRoomId != null && existingRoomId.isNotEmpty) {
          _isCreating.value = false;
          final openExisting = await widget.showExistingDmDialog(
            context,
            otherUserId: otherUserId,
            otherUserDisplayLabel: _selectedUsers.value.first.userIdDisplay,
            existingRoomId: existingRoomId,
          );
          if (context.mounted && openExisting == true) {
            widget.goBack(context, existingRoomId);
          }
          return;
        }

        final result = await model.createDirectRoom(userId: otherUserId);
        if (context.mounted) {
          result.fold(
            (id) {
              _isCreating.value = false;
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(context).pop(id);
              showCreateChatSnackBar(
                messenger,
                'Direct chat is ready.',
                kind: CreateChatSnackKind.success,
              );
            },
            (failure) {
              _isCreating.value = false;
              widget.showSnackBar(
                context,
                'Could not start direct chat: $failure',
              );
            },
          );
        }
      } else {
        // For group chat, use all selected users
        final userIds = _selectedUsers.value.map((u) => u.userId).toList();
        final result = await model.createGroupRoom(
          name: _groupNameController.text.trim(),
          userIds: userIds,
        );
        if (context.mounted) {
          result.fold(
            (id) {
              _isCreating.value = false;
              final messenger = ScaffoldMessenger.of(context);
              final name = _groupNameController.text.trim();
              Navigator.of(context).pop(id);
              showCreateChatSnackBar(
                messenger,
                'Group “$name” created.',
                kind: CreateChatSnackKind.success,
              );
            },
            (failure) {
              _isCreating.value = false;
              widget.showSnackBar(
                context,
                'Could not create group: $failure',
              );
            },
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        _isCreating.value = false;
        widget.showSnackBar(context, 'Something went wrong: $e');
      }
    }
  }
}
