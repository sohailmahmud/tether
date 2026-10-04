import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/camera_failure.dart';
import '../../../domain/entities/captured_photo.dart';
import '../../../domain/repositories/camera_repository.dart';
import 'camera_state.dart';

/// Owns the camera's lifecycle and the controls on the camera screen:
/// permission, opening and releasing the camera, zoom, focus and capture.
class CameraCubit extends Cubit<CameraState> {
  CameraCubit(this._camera) : super(const CameraStarting());

  final CameraRepository _camera;

  /// Opening, closing and capturing run one at a time, in call order, so a
  /// release can never overlap an open or dispose the camera mid-capture.
  Future<void> _queue = Future<void>.value();

  /// While the system permission dialog is up, the app goes inactive and
  /// resumes around it; those lifecycle events must not open or close the camera.
  bool _requestingPermission = false;

  // Kept across pause/resume so coming back restores the same view.
  double _zoom = 1;
  CapturedPhoto? _lastCapture;
  int _captureCount = 0;

  /// Called when the camera screen opens.
  Future<void> start() => _serialized(() async {
    if (await _camera.permissionStatus() == CameraPermission.granted) {
      await _open();
    } else {
      await _requestPermission();
    }
  });

  /// The user tapped "Allow camera".
  Future<void> requestPermission() => _serialized(_requestPermission);

  Future<void> openAppSettings() => _camera.openAppSettings();

  /// The user tapped "Try again" after the camera failed to start.
  Future<void> retry() => _serialized(_open);

  /// The app lost focus or went to the background: release the camera so
  /// other apps can use it, as the camera plugin requires.
  Future<void> onAppInactive() {
    if (_requestingPermission) return Future<void>.value();
    return _serialized(() async {
      if (state is! CameraReady) return;
      // Stop showing the preview before its controller is disposed.
      _emit(const CameraPaused());
      await _camera.close();
    });
  }

  /// The app is in the foreground again, possibly back from Settings.
  Future<void> onAppResumed() {
    if (_requestingPermission) return Future<void>.value();
    return _serialized(() async {
      switch (state) {
        case CameraPaused():
          await _open();
        case CameraPermissionRequired():
          if (await _camera.permissionStatus() == CameraPermission.granted) {
            await _open();
          }
        default:
          break;
      }
    });
  }

  /// Sets zoom from the buttons, slider or pinch, clamped to what the camera supports.
  void setZoom(double zoom) {
    final current = state;
    if (current is! CameraReady) return;
    final clamped = current.capabilities.clampZoom(zoom);
    if (clamped == current.zoom) return;
    _zoom = clamped;
    emit(current.copyWith(zoom: clamped));
    // Pinch sends many updates per second; the newest call wins and failures
    // are harmless, so they are not awaited.
    unawaited(_camera.setZoom(clamped));
  }

  /// Focuses at a point on the preview, [x] and [y] from 0 to 1.
  Future<void> focusAt(double x, double y) async {
    final current = state;
    if (current is! CameraReady || !current.capabilities.supportsFocusPoint) {
      return;
    }
    await _camera.focusAt(x.clamp(0, 1).toDouble(), y.clamp(0, 1).toDouble());
  }

  /// Takes a photo. Taps while a capture is in progress are ignored.
  Future<void> capture() {
    final current = state;
    if (current is! CameraReady || current.isCapturing) {
      return Future<void>.value();
    }
    emit(current.copyWith(isCapturing: true, captureFailed: false));
    return _serialized(() async {
      try {
        final photo = await _camera.capture();
        _lastCapture = photo;
        _captureCount++;
        _updateReady(
          (ready) => ready.copyWith(
            isCapturing: false,
            lastCapture: photo,
            captureCount: _captureCount,
          ),
        );
      } on CameraFailureException {
        _updateReady(
          (ready) => ready.copyWith(isCapturing: false, captureFailed: true),
        );
      }
    });
  }

  /// The capture failure has been shown to the user.
  void captureFailureShown() =>
      _updateReady((ready) => ready.copyWith(captureFailed: false));

  @override
  Future<void> close() async {
    await _queue;
    await _camera.close();
    return super.close();
  }

  Future<void> _requestPermission() async {
    _requestingPermission = true;
    try {
      final permission = await _camera.requestPermission();
      if (permission == CameraPermission.granted) {
        await _open();
      } else {
        _emit(
          CameraPermissionRequired(
            permanentlyDenied: permission == CameraPermission.permanentlyDenied,
          ),
        );
      }
    } finally {
      _requestingPermission = false;
    }
  }

  Future<void> _open() async {
    _emit(const CameraStarting());
    try {
      final capabilities = await _camera.openBackCamera();
      _zoom = capabilities.clampZoom(_zoom);
      if (_zoom != 1) await _camera.setZoom(_zoom);
      _emit(
        CameraReady(
          capabilities: capabilities,
          zoom: _zoom,
          lastCapture: _lastCapture,
          captureCount: _captureCount,
        ),
      );
    } on CameraFailureException catch (e) {
      _emit(CameraUnavailable(e.failure));
    }
  }

  Future<void> _serialized(Future<void> Function() operation) {
    final result = _queue.then((_) => operation());
    // A failed operation must not block the ones queued after it.
    _queue = result.catchError((Object _) {});
    return result;
  }

  void _updateReady(CameraReady Function(CameraReady) update) {
    final current = state;
    if (current is CameraReady) _emit(update(current));
  }

  /// Async work can finish after the screen has closed the cubit.
  void _emit(CameraState next) {
    if (!isClosed) emit(next);
  }
}
