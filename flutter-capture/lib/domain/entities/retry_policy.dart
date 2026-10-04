/// How long to wait before retrying a failed upload.
///
/// Exponential backoff: 30 s after the first failure, doubling each time, up
/// to 15 minutes. Backing off stops a dead connection from being hammered;
/// the cap keeps the wait short once it comes back. A new network connection
/// retries straight away regardless (see the sync worker).
abstract final class RetryPolicy {
  static const firstDelay = Duration(seconds: 30);
  static const maxDelay = Duration(minutes: 15);

  /// An "uploading" claim older than this is treated as abandoned (the app
  /// was killed mid-upload) and the batch is queued again.
  static const uploadLease = Duration(minutes: 5);

  /// Wait after [failedAttempts] consecutive failures (1 or more).
  static Duration delayAfter(int failedAttempts) {
    if (failedAttempts <= 1) return firstDelay;
    // Stop doubling well before an int overflow.
    final doublings = (failedAttempts - 1).clamp(0, 20);
    final delay = firstDelay * (1 << doublings);
    return delay > maxDelay ? maxDelay : delay;
  }
}
