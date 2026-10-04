import '../entities/camera_capabilities.dart';
import '../entities/captured_photo.dart';

/// Camera permission as the app needs to act on it.
enum CameraPermission {
  granted,

  /// Not granted; asking again shows the system dialog.
  denied,

  /// Not granted and the system will not ask again: only Settings can fix it.
  permanentlyDenied,
}

/// Access to the device camera. Opens at most one camera at a time.
abstract interface class CameraRepository {
  /// Current permission, without prompting the user.
  Future<CameraPermission> permissionStatus();

  /// Shows the system permission dialog when the system allows it.
  Future<CameraPermission> requestPermission();

  Future<void> openAppSettings();

  /// Opens the device's main back camera, closing any camera already open.
  ///
  /// Throws a `CameraFailureException` with `noBackCamera` or
  /// `initializationFailed`.
  Future<CameraCapabilities> openBackCamera();

  Future<void> setZoom(double zoom);

  /// Focuses (and meters exposure) at a point on the preview. [x] and [y] run
  /// from 0 to 1, with the origin at the preview's top-left corner.
  Future<void> focusAt(double x, double y);

  /// Throws a `CameraFailureException` with `captureFailed`.
  Future<CapturedPhoto> capture();

  /// Releases the camera. Safe to call when nothing is open.
  Future<void> close();
}
