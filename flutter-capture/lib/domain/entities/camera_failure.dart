/// Camera problems the user can be told about.
enum CameraFailure {
  /// The device has no back-facing camera.
  noBackCamera,

  /// The camera exists but could not be started, e.g. another app holds it.
  initializationFailed,

  /// A photo could not be taken or saved.
  captureFailed,
}

/// Thrown by a camera repository when an operation fails in a known way.
class CameraFailureException implements Exception {
  const CameraFailureException(this.failure, [this.cause]);

  final CameraFailure failure;

  /// The underlying platform error, for logs only.
  final Object? cause;

  @override
  String toString() => 'CameraFailureException($failure, $cause)';
}
