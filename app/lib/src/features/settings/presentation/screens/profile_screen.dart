import 'package:flutter/material.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _controller = TextEditingController();
  final _matrixService = MatrixService();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _loadDisplayName();
  }

  Future<void> _loadDisplayName() async {
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      final name = await _matrixService.client.getDisplayName();
      if (mounted) {
        _controller.text = name ?? '';
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load profile: $e';
        });
      }
    }
  }

  Future<void> _saveDisplayName() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() {
        _error = 'Display name cannot be empty';
        _success = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await _matrixService.client.setDisplayName(displayName: name);
      if (mounted) {
        setState(() {
          _saving = false;
          _success = 'Display name updated';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to save: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TerminalScreen(
      title: 'PROFILE',
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: TerminalContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('DISPLAY NAME', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'This is how others will see you in rooms and messages.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else ...[
                  TerminalTextField(
                    controller: _controller,
                    label: 'DISPLAY NAME',
                    hint: 'Enter your display name',
                    icon: Icons.badge,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    TerminalStatusMessage(
                      message: _error!,
                      isError: true,
                    ),
                  ],
                  if (_success != null) ...[
                    const SizedBox(height: 12),
                    TerminalStatusMessage(
                      message: _success!,
                      isSuccess: true,
                    ),
                  ],
                  const SizedBox(height: 24),
                  TerminalButton(
                    text: 'SAVE',
                    onPressed: _saving ? null : _saveDisplayName,
                    isLoading: _saving,
                    icon: Icons.save,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
