/// Why an upload attempt failed. Every reason is retried: the photos stay
/// queued until the server accepts them.
enum UploadFailureReason {
  /// No network connection at all.
  noConnection,

  /// The connection was too slow and the request timed out.
  timeout,

  /// The server answered with an error (e.g. 503).
  serverError,
}

/// Outcome of one call to the upload API.
sealed class UploadResult {
  const UploadResult();
}

final class UploadSucceeded extends UploadResult {
  const UploadSucceeded({required this.receiptId});

  /// The server's reference for the stored batch.
  final String receiptId;
}

final class UploadFailed extends UploadResult {
  const UploadFailed(this.reason, this.message);

  final UploadFailureReason reason;

  /// Shown to the user as the batch's last error.
  final String message;
}
