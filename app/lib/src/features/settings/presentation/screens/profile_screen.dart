import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:matrix/src/core/matrix_avatar_disk_cache.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/settings/domain/profile_local_cache.dart';
import 'package:matrix/src/features/settings/domain/profile_prefs.dart';
import 'package:matrix/src/features/settings/presentation/screens/profile_avatar_crop_screen.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';

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
  final _matrixUserIdController = TextEditingController();
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

    final client = _matrixService.client;
    final disk = await ProfileLocalCache.load();

    if (disk != null && !disk.isEmpty && mounted) {
      _displayNameController.text = disk.displayName;
      _initialsController.text = disk.initials;
      _avatarMxc = disk.avatarMxc.isEmpty ? null : disk.avatarMxc;
      _avatarPreviewBytes = null;
      final uidEarly = await client.loggedInUserId();
      if (!mounted) return;
      _matrixUserIdController.text = uidEarly ?? '';
      setState(() => _loading = false);
      unawaited(_applyAvatarPreview(_avatarMxc));
    }

    try {
      final userId = await client.loggedInUserId();
      final name = await client.getDisplayName();
      final initials = await client.getProfileInitials();

      String? mxc;
      try {
        final cached = await client.getCachedProfileAvatarMxc();
        if (cached != null && cached.trim().isNotEmpty) {
          mxc = cached.trim();
        }
      } catch (_) {}
      mxc ??= await client.getProfileAvatarMxc();
      var mxcTrim = mxc?.trim();
      if (mxcTrim != null && mxcTrim.isEmpty) mxcTrim = null;

      if (!mounted) return;

      _matrixUserIdController.text = userId ?? '';
      _displayNameController.text = name ?? '';
      _initialsController.text = initials ?? '';
      _avatarMxc = mxcTrim;
      ProfilePrefs.instance.setLocalAvatarMxc(mxcTrim);

      await ProfileLocalCache.save(
        displayName: _displayNameController.text,
        initials: _initialsController.text,
        avatarMxc: mxcTrim ?? '',
      );

      setState(() => _loading = false);

      await _applyAvatarPreview(mxcTrim);
    } catch (e) {
      if (!mounted) return;
      if (disk == null || disk.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Failed to load profile: $e';
        });
      } else {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _applyAvatarPreview(String? mxc) async {
    final uri = mxc?.trim();
    if (uri == null || uri.isEmpty) {
      if (mounted) {
        setState(() {
          _avatarPreviewBytes = null;
          _avatarLoading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _avatarLoading = true);
    try {
      final bytes = await MatrixAvatarDiskCache.instance.loadOrFetch(
        uri,
        () => _matrixService.client.fetchUserAvatarThumbnail(mxcUri: uri),
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

  Future<void> _pickAndUploadAvatar() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 92,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (bytes.isEmpty) return;

    if (!mounted) return;
    final cropped = await Navigator.of(context).push<Uint8List?>(
      MaterialPageRoute<Uint8List?>(
        fullscreenDialog: true,
        builder: (ctx) => ProfileAvatarCropScreen(imageBytes: bytes),
      ),
    );
    if (cropped == null || cropped.isEmpty) return;

    final normalized = _normalizeAvatarImageBytes(cropped, 'crop.jpg');
    final uploadBytes = normalized ?? cropped;
    const uploadMime = 'image/jpeg';

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
      await ProfileLocalCache.save(
        displayName: _displayNameController.text.trim(),
        initials: _initialsController.text.trim(),
        avatarMxc: mxc?.trim() ?? '',
      );
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
      await ProfileLocalCache.save(
        displayName: _displayNameController.text.trim(),
        initials: _initialsController.text.trim(),
        avatarMxc: '',
      );
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
      await ProfileLocalCache.save(
        displayName: displayName,
        initials: initialsRaw,
        avatarMxc: _avatarMxc?.trim() ?? '',
      );
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
    _matrixUserIdController.dispose();
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
                  'Initials are stored for this client (account data) and used in your message avatars. '
                  'This screen shows the last copy saved on this device first, then refreshes from the server; '
                  'the Matrix SDK also keeps your avatar MXC in its local state store after sync.',
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
                    controller: _matrixUserIdController,
                    label: 'MATRIX USER ID',
                    hint: 'Not available',
                    icon: Icons.alternate_email,
                    readOnly: true,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Read only — your unique account id on the homeserver.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
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
