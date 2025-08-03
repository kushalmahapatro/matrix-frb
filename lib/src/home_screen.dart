import 'dart:async';
import 'package:flutter/material.dart';
import 'package:matrix/src/rust/api/matrix_client.dart';
import 'package:matrix/src/login_screen.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix/src/theme/theme_switcher.dart';
import 'package:matrix/src/theme/theme_provider.dart';
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
    _loadRooms();
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

  Future<void> _loadRooms() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'LOADING MATRIX ROOMS...';
    });

    try {
      final rooms = await getRooms();
      final syncStatus = await getSyncStatus();

      if (!mounted) return;

      setState(() {
        _rooms = rooms;
        _syncStatus = syncStatus;
        _isLoading = false;
        _statusMessage = '';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _statusMessage = 'ERROR LOADING ROOMS: $e';
      });
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
        backgroundColor: Colors.black,
        foregroundColor: Colors.green,
        title: const Text(
          'MATRIX TERMINAL',
          style: TextStyle(
            color: Colors.green,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
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
                    Text(_statusMessage, style: MatrixTheme.warningStyle),
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
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          room.name ?? room.roomId,
          style: MatrixTheme.bodyStyle.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (room.topic != null) ...[
              const SizedBox(height: 4),
              Text(
                room.topic!,
                style: MatrixTheme.bodyStyle.copyWith(
                  color: MatrixTheme.primaryGreen.withOpacity(0.7),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  room.isEncrypted ? Icons.lock : Icons.lock_open,
                  color:
                      room.isEncrypted
                          ? MatrixTheme.primaryGreen
                          : MatrixTheme.warningOrange,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  room.isEncrypted ? 'ENCRYPTED' : 'UNENCRYPTED',
                  style: MatrixTheme.captionStyle.copyWith(
                    color:
                        room.isEncrypted
                            ? MatrixTheme.primaryGreen
                            : MatrixTheme.warningOrange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 16),
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
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: MatrixTheme.primaryGreen,
          size: 16,
        ),
        onTap: () {
          // TODO: Navigate to room chat
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ENTERING ROOM: ${room.name ?? room.roomId}'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }
}
