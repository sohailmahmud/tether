import 'package:equatable/equatable.dart';

import '../../../domain/entities/camera_capabilities.dart';
import '../../../domain/entities/camera_failure.dart';

/// What the camera screen shows.
sealed class CameraState extends Equatable {
  const CameraState();

  @override
  List<Object?> get props => [];
}

/// Checking permission or opening the camera.
final class CameraStarting extends CameraState {
  const CameraStarting();
}

/// Camera permission is missing.
final class CameraPermissionRequired extends CameraState {
  const CameraPermissionRequired({required this.permanentlyDenied});

  /// True when only system Settings can grant it.
  final bool permanentlyDenied;

  @override
  List<Object?> get props => [permanentlyDenied];
}

/// The camera can't be used (no back camera, or it failed to start).
final class CameraUnavailable extends CameraState {
  const CameraUnavailable(this.failure);

  final CameraFailure failure;

  @override
  List<Object?> get props => [failure];
}

/// The camera is released: the app is in the background or another screen
/// covers the camera.
final class CameraPaused extends CameraState {
  const CameraPaused();
}

/// The preview is live.
final class CameraReady extends CameraState {
  const CameraReady({
    required this.capabilities,
    required this.zoom,
    this.isCapturing = false,
    this.captureFailed = false,
  });

  final CameraCapabilities capabilities;
  final double zoom;
  final bool isCapturing;

  /// The last photo could not be taken or saved; cleared once the user has
  /// been told.
  final bool captureFailed;

  CameraReady copyWith({
    double? zoom,
    bool? isCapturing,
    bool? captureFailed,
  }) => CameraReady(
    capabilities: capabilities,
    zoom: zoom ?? this.zoom,
    isCapturing: isCapturing ?? this.isCapturing,
    captureFailed: captureFailed ?? this.captureFailed,
  );

  @override
  List<Object?> get props => [capabilities, zoom, isCapturing, captureFailed];
}
