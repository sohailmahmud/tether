import 'dart:developer' as developer;

import 'package:workmanager/workmanager.dart';

import '../domain/repositories/upload_queue_repository.dart';
import '../domain/usecases/process_upload_queue.dart';
import 'queue_change_channel.dart';
import 'sync_dependencies.dart';

/// Entry point of the background worker's isolate, started by WorkManager
/// when the device has a network connection, even if the app is closed.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Every change is announced so an open app updates its screens.
      final dependencies = await SyncDependencies.open(
        onQueueWrite: QueueChangeChannel.announce,
      );
      // The database is deliberately left open: on Android sqflite shares one
      // native connection with the app's isolate, and closing it here would
      // close it under the app.
      return runBackgroundSync(
        dependencies.processUploadQueue,
        dependencies.uploadQueue,
      );
    } on Object catch (error, stack) {
      developer.log(
        'Background sync failed',
        name: 'Sync',
        error: error,
        stackTrace: stack,
      );
      return false; // WorkManager retries later.
    }
  });
}

/// One background run. Returns true when nothing is left to upload, and
/// false to have WorkManager retry later (with backoff, once there is a
/// network): the platform's backoff paces background retries, so failed
/// batches don't wait for their in-app retry time here.
Future<bool> runBackgroundSync(
  ProcessUploadQueue processUploadQueue,
  UploadQueueRepository uploadQueue,
) async {
  final summary = await processUploadQueue(retryFailedNow: true);
  developer.log(
    'Background run: ${summary.uploaded} uploaded, ${summary.failed} failed'
    '${summary.stoppedOffline ? ', offline' : ''}',
    name: 'Sync',
  );
  return !await uploadQueue.hasUnfinishedUploads();
}
