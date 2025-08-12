import 'dart:async';
import 'package:flutter/material.dart';
import 'package:matrix/src/matrix_sync_service.dart';
import 'package:matrix/src/rust/api/matrix_client.dart';
import 'package:matrix/src/login_screen.dart';
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
  List<MatrixRoomInfo> _rooms = [];
  bool _isLoading = true;
  String _statusMessage = '';
  SyncStatus? _syncStatus;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _loadRooms(initial: true);
    MatrixSyncService().syncStream.listen((event) {
      _updateSyncStatus();
      _loadRooms();
    });

    listenRoomUpdates().listen((update) {
      if (mounted) {
        final index = _rooms.indexWhere((r) => r.roomId == update.roomId);

        if (index == -1) {
          _rooms.add(update);
        } else {
          // Update existing room if it already exists

          if (_rooms[index].latestEventTimestamp != null &&
              _rooms[index].latestEventTimestamp !=
                  update.latestEventTimestamp) {
            _rooms.removeAt(index);
            _rooms.add(update);
          }
        }
        setState(() {});
      }
    });
    _startSyncTimer();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  void _startSyncTimer() {
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateSyncStatus();
    });
  }

  Future<void> _loadRooms({bool initial = false}) async {
    setState(() {
      if (initial) {
        _isLoading = true;
        _statusMessage = 'LOADING...';
      }
    });

    try {
      final rooms = await getRooms();
      final syncStatus = await getSyncStatus();

      if (!mounted) return;

      setState(() {
        _rooms = rooms;
        _syncStatus = syncStatus;
        if (initial) {
          _isLoading = false;
          _statusMessage = '';
        }
      });
    } catch (e) {
      if (!mounted) return;

      if (initial) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'ERROR LOADING ROOMS: $e';
        });
      }
    }
  }

  Future<void> _updateSyncStatus() async {
    try {
      final syncStatus = await getSyncStatus();
      if (mounted) {
        setState(() {
          _syncStatus = syncStatus;
        });
      }
    } catch (e) {
      // Silently handle sync status errors
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
                  if (_syncStatus != null) ...[
                    Icon(
                      _syncStatus!.isSyncing ? Icons.sync : Icons.sync_disabled,
                      color:
                          _syncStatus!.isSyncing
                              ? MatrixTheme.primaryGreen
                              : MatrixTheme.warningOrange,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _syncStatus!.isSyncing ? 'SYNCING' : 'IDLE',
                      style: TextStyle(
                        color:
                            _syncStatus!.isSyncing
                                ? MatrixTheme.primaryGreen
                                : MatrixTheme.warningOrange,
                        fontSize: 12,
                        fontFamily: MatrixTheme.fontFamily,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'ROOMS: ${_syncStatus!.roomsCount}',
                      style: MatrixTheme.captionStyle,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'MESSAGES: ${_syncStatus!.messagesCount}',
                      style: MatrixTheme.captionStyle,
                    ),
                  ],

                  const Spacer(),

                  // Status Message
                  if (_statusMessage.isNotEmpty)
                    Flexible(
                      child: Text(
                        _statusMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MatrixTheme.warningStyle,
                      ),
                    ),
                ],
              ),
            ),

            // Rooms List
            Expanded(
              child:
                  _isLoading
                      ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                MatrixTheme.primaryGreen,
                              ),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'LOADING MATRIX...',
                              style: MatrixTheme.subtitleStyle,
                            ),
                          ],
                        ),
                      )
                      : _rooms.isEmpty
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

  Widget _buildRoomCard(MatrixRoomInfo room) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: MatrixTheme.getCardDecoration(
        context.read<ThemeProvider>().isDarkMode,
      ),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                room.name ?? room.roomId,
                style: MatrixTheme.bodyStyle.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.people,
                  color: MatrixTheme.primaryGreen,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  '${room.memberCount} MEMBERS',
                  style: MatrixTheme.captionStyle,
                ),
              ],
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (room.topic != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      room.topic!,
                      style: MatrixTheme.bodyStyle.copyWith(
                        color: MatrixTheme.primaryGreen.withValues(alpha: 0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(room.roomId, style: MatrixTheme.captionStyle),
              const SizedBox(height: 4),
              Text(
                room.latestEventTimestamp.toString(),
                style: MatrixTheme.bodyStyle,
              ),
              const SizedBox(height: 4),
              Text(
                room.latestEvent?.content.toString() ?? '',
                style: MatrixTheme.bodyStyle,
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: MatrixTheme.primaryGreen,
          size: 16,
        ),
        onTap: () {
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder:
                  (context, animation, secondaryAnimation) => TimelineScreen(
                    roomId: room.roomId,
                    roomName: room.name ?? room.roomId,
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
