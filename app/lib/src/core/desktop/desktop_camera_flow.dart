import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

/// Enumerates cameras; on desktop may return multiple devices (e.g. webcams).
Future<CameraDescription?> pickDesktopCameraDescription(
  BuildContext context,
) async {
  List<CameraDescription> cameras;
  try {
    cameras = await availableCameras();
  } catch (_) {
    cameras = [];
  }
  if (cameras.isEmpty) return null;
  if (cameras.length == 1) return cameras.first;
  if (!context.mounted) return null;
  return showDialog<CameraDescription>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: MatrixTheme.terminalBackground,
        title: Text(
          'Choose camera',
          style: TextStyle(
            fontFamily: MatrixTheme.fontFamily,
            color: MatrixTheme.matrixGreen,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < cameras.length; i++)
                ListTile(
                  leading: Icon(
                    Icons.videocam_outlined,
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                  title: Text(
                    cameras[i].name.isNotEmpty
                        ? cameras[i].name
                        : 'Camera ${i + 1}',
                  ),
                  subtitle: Text(
                    '${cameras[i].lensDirection.name} · ${cameras[i].sensorOrientation}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  onTap: () => Navigator.pop(ctx, cameras[i]),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
}

/// Live preview + single-frame capture (desktop / non-web).
class DesktopCameraCaptureDialog extends StatefulWidget {
  const DesktopCameraCaptureDialog({super.key, required this.camera});

  final CameraDescription camera;

  @override
  State<DesktopCameraCaptureDialog> createState() =>
      _DesktopCameraCaptureDialogState();
}

class _DesktopCameraCaptureDialogState extends State<DesktopCameraCaptureDialog> {
  CameraController? _controller;
  bool _ready = false;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final c = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _ready = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
      try {
        await c.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return AlertDialog(
        backgroundColor: MatrixTheme.terminalBackground,
        title: const Text('Camera'),
        content: Text(_error!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
    if (!_ready || _controller == null) {
      return AlertDialog(
        backgroundColor: MatrixTheme.terminalBackground,
        content: const SizedBox(
          width: 200,
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return AlertDialog(
      backgroundColor: MatrixTheme.terminalBackground,
      title: Text(
        'Take photo',
        style: TextStyle(fontFamily: MatrixTheme.fontFamily),
      ),
      content: SizedBox(
        width: 480,
        height: 360,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CameraPreview(_controller!),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _capture,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Capture'),
        ),
      ],
    );
  }
}
