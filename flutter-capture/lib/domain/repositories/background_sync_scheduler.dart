/// Asks the platform to run the upload engine in the background, when the
/// device has a network connection, even if the app has been closed.
abstract interface class BackgroundSyncScheduler {
  /// Schedules a background upload run unless one is already scheduled.
  Future<void> scheduleUpload();
}
