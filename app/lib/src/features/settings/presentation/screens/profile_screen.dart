import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:matrix/src/core/matrix_avatar_disk_cache.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/settings/domain/profile_prefs.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';

String _mimeFromImagePath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
    return 'image/heic';
  }
  return 'image/jpeg';
}

/// Decodes raster images, applies EXIF orientation into pixels, then re-encodes
/// (JPEG for photos, PNG when the source was PNG so alpha is kept).
Uint8List? _normalizeAvatarImageBytes(
  Uint8List raw,
  String path, {
  int jpegQuality = 88,
}) {
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return Uint8List.fromList(img.encodePng(oriented));
    }
    return Uint8List.fromList(
      img.encodeJpg(oriented, quality: jpegQuality),
    );
  } catch (_) {
    return null;
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _displayNameController = TextEditingController();
  final _initialsController = TextEditingController();
  final _matrixService = MatrixService();
  final _picker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;
  String? _avatarMxc;
  Uint8List? _avatarPreviewBytes;
  bool _avatarLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      final client = _matrixService.client;
      final name = await client.getDisplayName();
      final initials = await client.getProfileInitials();
      final mxc = await client.getProfileAvatarMxc();
      if (!mounted) return;
      _displayNameController.text = name ?? '';
      _initialsController.text = initials ?? '';
      _avatarMxc = mxc;
      _avatarPreviewBytes = null;
      ProfilePrefs.instance.setLocalAvatarMxc(mxc);
      setState(() => _loading = false);
      final uri = mxc?.trim();
      if (uri != null && uri.isNotEmpty) {
        setState(() => _avatarLoading = true);
        try {
          final bytes = await MatrixAvatarDiskCache.instance.loadOrFetch(
            uri,
            () => client.fetchUserAvatarThumbnail(mxcUri: uri),
          );
          if (mounted) {
            setState(() {
              _avatarPreviewBytes = bytes;
              _avatarLoading = false;
            });
          }
        } catch (_) {
          if (mounted) setState(() => _avatarLoading = false);
        }
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

  Future<void> _pickAndUploadAvatar() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 88,
    );
    if (x == null) return;
    final path = x.path;
    final bytes = await x.readAsBytes();
    if (bytes.isEmpty) return;

    final normalized = _normalizeAvatarImageBytes(bytes, path);
    final uploadBytes = normalized ?? bytes;
    final uploadMime = _mimeFromImagePath(path);

    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await _matrixService.client.uploadProfileAvatar(
        mimeType: uploadMime,
        data: uploadBytes,
      );
      final mxc = await _matrixService.client.getProfileAvatarMxc();
      if (!mounted) return;
      setState(() {
        _avatarMxc = mxc;
        _avatarPreviewBytes = uploadBytes;
        _saving = false;
        _success = 'Profile picture updated';
      });
      ProfilePrefs.instance.setLocalAvatarMxc(mxc);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Upload failed: $e';
        });
      }
    }
  }

  Future<void> _removeAvatar() async {
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await _matrixService.client.removeProfileAvatar();
      if (!mounted) return;
      setState(() {
        _avatarMxc = null;
        _avatarPreviewBytes = null;
        _saving = false;
        _success = 'Profile picture removed';
      });
      ProfilePrefs.instance.setLocalAvatarMxc(null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to remove picture: $e';
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    final displayName = _displayNameController.text.trim();
    final initialsRaw = _initialsController.text.trim();
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await _matrixService.client.setDisplayName(displayName: displayName);
      await _matrixService.client.setProfileInitials(
        initials: initialsRaw.isEmpty ? null : initialsRaw,
      );
      ProfilePrefs.instance.setLocalInitials(
        initialsRaw.isEmpty ? null : initialsRaw,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _success = 'Profile saved';
      });
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
    _displayNameController.dispose();
    _initialsController.dispose();
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
                Text('IDENTITY', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Display name and picture are shared with other Matrix users. '
                  'Initials are stored for this client (account data) and used in your message avatars.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else ...[
                  Center(
                    child: Column(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.65,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: _avatarLoading
                                ? const SizedBox(
                                    width: 96,
                                    height: 96,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : _avatarPreviewBytes != null &&
                                        _avatarPreviewBytes!.isNotEmpty
                                    ? Image.memory(
                                        _avatarPreviewBytes!,
                                        width: 96,
                                        height: 96,
                                        fit: BoxFit.cover,
                                      )
                                    : SizedBox(
                                        width: 96,
                                        height: 96,
                                        child: ColoredBox(
                                          color: theme.colorScheme
                                              .surfaceContainerHighest,
                                          child: Icon(
                                            Icons.person_outline,
                                            size: 48,
                                            color: theme.colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TerminalButton(
                              text: 'UPLOAD PHOTO',
                              onPressed: _saving ? null : _pickAndUploadAvatar,
                              icon: Icons.photo_library_outlined,
                            ),
                            if (_avatarMxc != null &&
                                _avatarMxc!.trim().isNotEmpty)
                              TerminalButton(
                                text: 'REMOVE PHOTO',
                                onPressed: _saving ? null : _removeAvatar,
                                icon: Icons.delete_outline,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  TerminalTextField(
                    controller: _displayNameController,
                    label: 'DISPLAY NAME / NICKNAME',
                    hint: 'How you appear in rooms',
                    icon: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 16),
                  TerminalTextField(
                    controller: _initialsController,
                    label: 'INITIALS (OPTIONAL)',
                    hint: 'e.g. JD — avatar fallback for your messages',
                    icon: Icons.text_fields,
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
                    text: 'SAVE PROFILE',
                    onPressed: _saving ? null : _saveProfile,
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
