import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../data/repositories/plugin_camera_repository.dart';

/// Live preview for [PluginCameraRepository]. Lives in the composition root so
/// the presentation layer never imports the camera plugin.
class PluginCameraPreview extends StatelessWidget {
  const PluginCameraPreview({super.key, required this.repository});

  final PluginCameraRepository repository;

  @override
  Widget build(BuildContext context) {
    final controller = repository.controller;
    // The screen only asks for a preview while the camera is ready, but a
    // frame can still land between release and rebuild.
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return CameraPreview(controller);
  }
}
