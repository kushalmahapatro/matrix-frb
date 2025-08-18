import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:matrix/src/create_room_screen.dart';
import 'package:matrix/src/login_screen.dart';
import 'package:matrix/src/rust/matrix/authentication.dart';
import 'package:matrix/src/rust/matrix/rooms.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix/src/theme/theme_switcher.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:matrix/src/timeline_screen.dart';
import 'package:provider/provider.dart';

enum ChatType { all, invited, direct, group }

class ChatListingScreen extends StatefulWidget {
  const ChatListingScreen({super.key});

  @override
  State<ChatListingScreen> createState() => _ChatListingScreenState();
}

class _ChatListingScreenState extends State<ChatListingScreen> {
  List<RoomUpdate> _rooms = [];
  bool _loading = false;
  ChatType selectedChatType = ChatType.all;

  @override
  void initState() {
    super.initState();
    _loading = true;
    _loadRooms(initial: true);
    subscribeToAllRoomUpdates().listen((event) {
      if (!mounted) return;

      switch (event.updateType) {
        case UpdateType.joined:
          final int index = _rooms.indexWhere(
            (element) => element.roomId == event.roomId,
          );
          _rooms[index] = event;

          break;
        case UpdateType.left:
          final int index = _rooms.indexWhere(
            (element) => element.roomId == event.roomId,
          );
          _rooms.removeAt(index);

          break;
        case UpdateType.invited:
          _rooms.add(event);

          break;
        case UpdateType.knocked:
          break;
      }

      _rooms.sort((a, b) {
        final aTimestamp = (a.message?.timestamp ?? BigInt.from(0)).toInt();
        final bTimestamp = (b.message?.timestamp ?? BigInt.from(0)).toInt();
        return bTimestamp.compareTo(aTimestamp);
      });

      setState(() {});
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadRooms({bool initial = false}) async {
    try {
      // final rooms = await getRooms();
      final rooms = await getAllRooms();

      if (!mounted) return;

      _rooms = rooms;
      _rooms.sort((a, b) {
        final aTimestamp = (a.message?.timestamp ?? BigInt.from(0)).toInt();
        final bTimestamp = (b.message?.timestamp ?? BigInt.from(0)).toInt();
        return bTimestamp.compareTo(aTimestamp);
      });
      _loading = false;

      setState(() {});
    } catch (e) {
      if (!mounted) return;
    }
  }

  Future<void> _logout() async {
    try {
      await logout();
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder:
              (context, animation, secondaryAnimation) => const LoginScreen(),
          transitionDuration: const Duration(milliseconds: 800),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('LOGOUT ERROR: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('MATRIX', style: MatrixTheme.titleStyle),
        actions: [
          const ThemeSwitcher(),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRooms),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: context.read<ThemeProvider>().backgroundGradient,
        ),
        child: Column(
          children: [
            // Status Bar
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: chatTypeGroupingWidget(),
            ),

            // Rooms List
            Expanded(
              child:
                  _loading && _rooms.isEmpty
                      ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.chat_bubble_outline,
                              color: MatrixTheme.primaryGreen,
                              size: 64,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'NO ROOMS FOUND',
                              style: MatrixTheme.titleStyle,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'JOIN OR CREATE A ROOM TO BEGIN',
                              style: MatrixTheme.bodyStyle,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _loadRooms,
                              style: MatrixTheme.primaryButtonStyle,
                              child: const Text(
                                'REFRESH',
                                style: MatrixTheme.buttonStyle,
                              ),
                            ),
                          ],
                        ),
                      )
                      : chatListWidget(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.of(context).push<String>(
            PageRouteBuilder(
              pageBuilder:
                  (context, animation, secondaryAnimation) =>
                      const CreateRoomScreen(),
              transitionDuration: const Duration(milliseconds: 800),
              transitionsBuilder: (
                context,
                animation,
                secondaryAnimation,
                child,
              ) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );

          if (result != null) {
            // Room was created, refresh the room list
            _loadRooms();
          }
        },
        backgroundColor: context.read<ThemeProvider>().textColor,
        foregroundColor: context.read<ThemeProvider>().backgroundColor,
        child: const Icon(Icons.add),
      ),
    );
  }

  @Preview(name: 'Chat Listing')
  ListView chatListWidget() {
    List<RoomUpdate> previewRooms = switch (selectedChatType) {
      ChatType.all => _rooms,
      ChatType.invited =>
        _rooms
            .where((element) => element.updateType == UpdateType.invited)
            .toList(),
      ChatType.direct =>
        _rooms.where((element) => element.isDm == true).toList(),
      ChatType.group =>
        _rooms.where((element) => element.isDm == false).toList(),
    };

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: previewRooms.length,
      itemBuilder: (context, index) {
        final room = previewRooms[index];
        return _buildRoomCard(room);
      },
    );
  }

  @Preview(name: 'Chat type Group')
  SizedBox chatTypeGroupingWidget() {
    String getCount(ChatType type) {
      switch (type) {
        case ChatType.all:
          return _rooms.length.toString();
        case ChatType.invited:
          return _rooms
              .where((element) => element.updateType == UpdateType.invited)
              .length
              .toString();
        case ChatType.direct:
          return _rooms
              .where((element) => element.isDm == true)
              .length
              .toString();
        case ChatType.group:
          return _rooms
              .where((element) => element.isDm == false)
              .length
              .toString();
      }
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children:
            ChatType.values.map((type) {
              return InkWell(
                onTap: () {
                  setState(() {
                    selectedChatType = type;
                  });
                },
                child: Container(
                  padding: EdgeInsets.all(10),
                  decoration:
                      type == selectedChatType
                          ? BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: MatrixTheme.primaryGreen,
                                width: 2,
                              ),
                            ),
                          )
                          : null,
                  child: Row(
                    children: [
                      Text(
                        type.name.toUpperCase(),
                        style: MatrixTheme.bodyStyle.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      Container(
                        height: 16,
                        width: 16,
                        alignment: Alignment.center,
                        margin: EdgeInsetsDirectional.only(start: 8),
                        decoration: BoxDecoration(
                          color: MatrixTheme.primaryGreen,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          getCount(type),
                          style: MatrixTheme.bodyStyle.copyWith(
                            color: MatrixTheme.darkBackground,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildRoomCard(RoomUpdate room) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),

      child: InkWell(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.displayName ?? room.roomId,
                    style: MatrixTheme.bodyStyle.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  if (room.message != null)
                    Text(
                      room.message!.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MatrixTheme.labelStyle.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),

            if ((room.unreadMessages ?? BigInt.from(0)) > BigInt.from(0))
              Container(
                height: 16,
                width: 16,
                decoration: BoxDecoration(
                  color: MatrixTheme.primaryGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    room.unreadMessages.toString(),
                    style: MatrixTheme.bodyStyle.copyWith(
                      color: MatrixTheme.darkBackground,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),

        onTap: () {
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder:
                  (context, animation, secondaryAnimation) => TimelineScreen(
                    roomId: room.roomId,
                    roomName: room.displayName ?? room.roomId,
                  ),
              transitionDuration: const Duration(milliseconds: 800),
              transitionsBuilder: (
                context,
                animation,
                secondaryAnimation,
                child,
              ) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );
        },
      ),
    );
  }
}
