import 'dart:developer' as developer;

import 'package:camera/camera.dart';
import 'package:flutter/painting.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

import '../../domain/entities/camera_capabilities.dart';
import '../../domain/entities/camera_failure.dart';
import '../../domain/entities/captured_photo.dart';
import '../../domain/repositories/camera_repository.dart';

/// [CameraRepository] backed by the `camera` and `permission_handler` plugins.
class PluginCameraRepository implements CameraRepository {
  PluginCameraRepository({
    this._loadCameras = availableCameras,
    this._clock = DateTime.now,
  });

  final Future<List<CameraDescription>> Function() _loadCameras;
  final DateTime Function() _clock;

  CameraController? _controller;

  /// The open camera, for rendering its preview only. Null when closed.
  /// Everything else goes through the [CameraRepository] methods.
  CameraController? get controller => _controller;

  @override
  Future<CameraPermission> permissionStatus() async =>
      _toCameraPermission(await permissions.Permission.camera.status);

  @override
  Future<CameraPermission> requestPermission() async =>
      _toCameraPermission(await permissions.Permission.camera.request());

  @override
  Future<void> openAppSettings() async {
    await permissions.openAppSettings();
  }

  @override
  Future<CameraCapabilities> openBackCamera() async {
    await close();

    final List<CameraDescription> cameras;
    try {
      cameras = await _loadCameras();
    } on CameraException catch (e) {
      throw CameraFailureException(CameraFailure.initializationFailed, e);
    }
    // The first back camera is the device's main (logical) one. On phones that
    // combine lenses behind it, its minimum zoom goes below 1x for ultra-wide.
    final back = cameras
        .where((c) => c.lensDirection == CameraLensDirection.back)
        .firstOrNull;
    if (back == null) {
      throw const CameraFailureException(CameraFailure.noBackCamera);
    }

    final controller = CameraController(
      back,
      // 1080p: sharp enough for documentation photos while keeping uploads
      // small on slow connections.
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
      final capabilities = CameraCapabilities(
        minZoom: await controller.getMinZoomLevel(),
        maxZoom: await controller.getMaxZoomLevel(),
        supportsFocusPoint: controller.value.focusPointSupported,
        previewAspectRatio: controller.value.aspectRatio,
      );
      _controller = controller;
      return capabilities;
    } on CameraException catch (e) {
      await controller.dispose();
      throw CameraFailureException(CameraFailure.initializationFailed, e);
    }
  }

  @override
  Future<void> setZoom(double zoom) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setZoomLevel(zoom);
    } on CameraException catch (e) {
      // Not worth interrupting the user: the next zoom change retries.
      developer.log('Zoom failed: ${e.code}', name: 'Camera');
    }
  }

  @override
  Future<void> focusAt(double x, double y) async {
    final controller = _controller;
    if (controller == null) return;
    final point = Offset(x, y);
    try {
      await controller.setFocusPoint(point);
      if (controller.value.exposurePointSupported) {
        await controller.setExposurePoint(point);
      }
    } on CameraException catch (e) {
      developer.log('Focus failed: ${e.code}', name: 'Camera');
    }
  }

  @override
  Future<CapturedPhoto> capture() async {
    final controller = _controller;
    if (controller == null) {
      throw const CameraFailureException(CameraFailure.captureFailed);
    }
    try {
      final file = await controller.takePicture();
      return CapturedPhoto(path: file.path, capturedAt: _clock());
    } on CameraException catch (e) {
      throw CameraFailureException(CameraFailure.captureFailed, e);
    }
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }

  static CameraPermission _toCameraPermission(
    permissions.PermissionStatus status,
  ) => switch (status) {
    permissions.PermissionStatus.granted ||
    permissions.PermissionStatus.limited => CameraPermission.granted,
    permissions.PermissionStatus.permanentlyDenied ||
    permissions.PermissionStatus.restricted =>
      CameraPermission.permanentlyDenied,
    _ => CameraPermission.denied,
  };
}
