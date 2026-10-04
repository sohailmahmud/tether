import 'dart:async';

import 'package:tether_capture/domain/entities/camera_capabilities.dart';
import 'package:tether_capture/domain/entities/camera_failure.dart';
import 'package:tether_capture/domain/entities/captured_photo.dart';
import 'package:tether_capture/domain/repositories/camera_repository.dart';

const backCamera = CameraCapabilities(
  minZoom: 1,
  maxZoom: 8,
  supportsFocusPoint: true,
  previewAspectRatio: 4 / 3,
);

/// In-memory [CameraRepository] that records calls and can be told to fail.
class FakeCameraRepository implements CameraRepository {
  FakeCameraRepository({
    this.status = CameraPermission.granted,
    CameraPermission? requestResult,
    this.capabilities = backCamera,
  }) : requestResult = requestResult ?? status;

  CameraPermission status;
  CameraPermission requestResult;
  CameraCapabilities capabilities;

  /// When set, openBackCamera() throws this failure.
  CameraFailure? openFailure;
  bool captureFails = false;

  /// When set, capture() throws it: an unexpected error, not a camera failure.
  Object? captureError;

  /// When set, capture() waits for it, simulating a slow shutter.
  Completer<void>? captureGate;

  /// When set, requestPermission() waits for it, as if the dialog were open.
  Completer<void>? requestGate;

  int requestCount = 0;
  int openCount = 0;
  int closeCount = 0;
  int captureCount = 0;
  bool isOpen = false;
  bool settingsOpened = false;
  final List<double> zoomCalls = [];
  final List<(double, double)> focusCalls = [];

  @override
  Future<CameraPermission> permissionStatus() async => status;

  @override
  Future<CameraPermission> requestPermission() async {
    requestCount++;
    await requestGate?.future;
    status = requestResult;
    return status;
  }

  @override
  Future<void> openAppSettings() async => settingsOpened = true;

  @override
  Future<CameraCapabilities> openBackCamera() async {
    openCount++;
    final failure = openFailure;
    if (failure != null) throw CameraFailureException(failure);
    isOpen = true;
    return capabilities;
  }

  @override
  Future<void> setZoom(double zoom) async => zoomCalls.add(zoom);

  @override
  Future<void> focusAt(double x, double y) async => focusCalls.add((x, y));

  @override
  Future<CapturedPhoto> capture() async {
    captureCount++;
    await captureGate?.future;
    if (captureError case final error?) throw error;
    if (captureFails) {
      throw const CameraFailureException(CameraFailure.captureFailed);
    }
    return CapturedPhoto(
      path: '/photos/$captureCount.jpg',
      capturedAt: DateTime(2026, 10, 4, 12, captureCount),
    );
  }

  @override
  Future<void> close() async {
    if (isOpen) closeCount++;
    isOpen = false;
  }
}
