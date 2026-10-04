import 'package:equatable/equatable.dart';

import '../../../domain/entities/camera_capabilities.dart';
import '../../../domain/entities/camera_failure.dart';
import '../../../domain/entities/captured_photo.dart';

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

/// The app is in the background and the camera is released.
final class CameraPaused extends CameraState {
  const CameraPaused();
}

/// The preview is live.
final class CameraReady extends CameraState {
  const CameraReady({
    required this.capabilities,
    required this.zoom,
    this.isCapturing = false,
    this.lastCapture,
    this.captureCount = 0,
    this.captureFailed = false,
  });

  final CameraCapabilities capabilities;
  final double zoom;
  final bool isCapturing;

  /// Most recent photo this session, for the thumbnail.
  final CapturedPhoto? lastCapture;
  final int captureCount;

  /// The last capture attempt failed; cleared once the user has been told.
  final bool captureFailed;

  CameraReady copyWith({
    double? zoom,
    bool? isCapturing,
    CapturedPhoto? lastCapture,
    int? captureCount,
    bool? captureFailed,
  }) => CameraReady(
    capabilities: capabilities,
    zoom: zoom ?? this.zoom,
    isCapturing: isCapturing ?? this.isCapturing,
    lastCapture: lastCapture ?? this.lastCapture,
    captureCount: captureCount ?? this.captureCount,
    captureFailed: captureFailed ?? this.captureFailed,
  );

  @override
  List<Object?> get props => [
    capabilities,
    zoom,
    isCapturing,
    lastCapture,
    captureCount,
    captureFailed,
  ];
}
