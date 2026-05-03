import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';

/// Square crop for avatars; user pans/zooms and confirms the visible area.
class ProfileAvatarCropScreen extends StatefulWidget {
  const ProfileAvatarCropScreen({
    super.key,
    required this.imageBytes,
    this.title = 'CROP PHOTO',
    this.hintText =
        'Pinch and drag to position. The square area is what others see in your profile.',
  });

  final Uint8List imageBytes;
  final String title;
  final String hintText;

  @override
  State<ProfileAvatarCropScreen> createState() =>
      _ProfileAvatarCropScreenState();
}

class _ProfileAvatarCropScreenState extends State<ProfileAvatarCropScreen> {
  final _cropController = CropController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return TerminalScreen(
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              widget.hintText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Crop(
                image: widget.imageBytes,
                controller: _cropController,
                aspectRatio: 1,
                interactive: true,
                baseColor: theme.scaffoldBackgroundColor,
                maskColor: Colors.black.withValues(alpha: 0.55),
                onCropped: (result) {
                  switch (result) {
                    case CropSuccess(:final croppedImage):
                      Navigator.of(context).pop<Uint8List>(croppedImage);
                    case CropFailure(:final cause):
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not crop: $cause')),
                      );
                  }
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TerminalButton(
                    text: 'CANCEL',
                    onPressed: () => Navigator.of(context).pop<Uint8List?>(),
                    isPrimary: false,
                    icon: Icons.close,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TerminalButton(
                    text: 'USE CROP',
                    onPressed: () => _cropController.crop(),
                    icon: Icons.check,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
