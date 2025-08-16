import 'dart:async';
import 'package:flutter/material.dart';
import 'package:matrix/src/login_screen.dart';
import 'package:matrix/src/rust/matrix/authentication.dart';
import 'package:matrix/src/rust/matrix/rooms.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix/src/theme/theme_switcher.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:matrix/src/timeline_screen.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<RoomUpdate> _rooms = [];
  bool _loading = false;

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
        title: const Text('MATRIX TERMINAL', style: MatrixTheme.titleStyle),
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
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: MatrixTheme.primaryGreen, width: 1),
                ),
              ),
              child: Row(
                children: [
                  // Sync Status
                  Icon(Icons.sync, color: MatrixTheme.primaryGreen, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'SYNCING',
                    style: TextStyle(
                      color: MatrixTheme.primaryGreen,
                      fontSize: 12,
                      fontFamily: MatrixTheme.fontFamily,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'ROOMS: ${_rooms.length}',
                    style: MatrixTheme.captionStyle,
                  ),
                  const SizedBox(width: 16),

                  // Text(
                  //   'MESSAGES: ${_syncStatus!.messagesCount}',
                  //   style: MatrixTheme.captionStyle,
                  // ),
                ],
              ),
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
                      : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rooms.length,
                        itemBuilder: (context, index) {
                          final room = _rooms[index];
                          return _buildRoomCard(room);
                        },
                      ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: Implement create room functionality
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('CREATE ROOM - COMING SOON'),
              backgroundColor: Colors.green,
            ),
          );
        },
        backgroundColor: context.read<ThemeProvider>().textColor,
        foregroundColor: context.read<ThemeProvider>().backgroundColor,
        child: const Icon(Icons.add),
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
