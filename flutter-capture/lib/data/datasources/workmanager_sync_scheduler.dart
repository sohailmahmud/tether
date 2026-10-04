import 'package:workmanager/workmanager.dart';

import '../../domain/repositories/background_sync_scheduler.dart';

/// [BackgroundSyncScheduler] on Android's WorkManager (via `workmanager`).
///
/// One unique task, run only when the device has a network connection. If it
/// reports unfinished work, WorkManager retries it with exponential backoff
/// from 30 s, again only once there is a network.
class WorkmanagerSyncScheduler implements BackgroundSyncScheduler {
  WorkmanagerSyncScheduler([Workmanager? workmanager])
    : _workmanager = workmanager ?? Workmanager();

  static const uniqueName = 'tether.upload-queue';
  static const taskName = 'uploadQueue';

  final Workmanager _workmanager;

  @override
  Future<void> scheduleUpload() => _workmanager.registerOneOffTask(
    uniqueName,
    taskName,
    constraints: Constraints(networkType: NetworkType.connected),
    // Already scheduled or running: keep that one rather than restart it.
    existingWorkPolicy: ExistingWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(seconds: 30),
  );
}
