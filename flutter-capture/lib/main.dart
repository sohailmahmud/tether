import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:workmanager/workmanager.dart';

import 'app/app.dart';
import 'app/app_bloc_observer.dart';
import 'app/background_sync.dart';
import 'app/plugin_camera_preview.dart';
import 'app/queue_change_channel.dart';
import 'app/startup_failure_app.dart';
import 'app/sync_dependencies.dart';
import 'data/datasources/workmanager_sync_scheduler.dart';
import 'data/repositories/plugin_camera_repository.dart';
import 'data/repositories/sqflite_upload_queue_repository.dart';
import 'presentation/uploads/cubit/sync_cubit.dart';

/// Composition root: creates the concrete dependencies and starts the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Bloc.observer = const AppBlocObserver();
  // Portrait only: the viewfinder layout and the tap-to-focus mapping assume it.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // The same engine setup the background worker builds in its own isolate.
  final SyncDependencies sync;
  try {
    sync = await SyncDependencies.open();
  } on Object catch (error, stack) {
    developer.log(
      'Storage could not be opened',
      name: 'Startup',
      error: error,
      stackTrace: stack,
    );
    runApp(const StartupFailureApp());
    return;
  }
  // Uploads done by the background worker reach open screens through this.
  QueueChangeChannel.listen(sync.uploadQueue.notifyExternalChange);
  unawaited(_deleteOrphanedPhotos(sync.uploadQueue));
  try {
    await Workmanager().initialize(backgroundSyncDispatcher);
  } on Object catch (error, stack) {
    // Uploads still run while the app is open; scheduling the background
    // run then fails and is logged on each attempt.
    developer.log(
      'Background worker unavailable',
      name: 'Startup',
      error: error,
      stackTrace: stack,
    );
  }
  final backgroundSync = WorkmanagerSyncScheduler();
  final camera = PluginCameraRepository();

  runApp(
    TetherCaptureApp(
      cameraRepository: camera,
      uploadQueueRepository: sync.uploadQueue,
      mockServerSettings: sync.mockServerSettings,
      createSyncCubit: () => SyncCubit(
        processQueue: sync.processUploadQueue,
        queue: sync.uploadQueue,
        backgroundSync: backgroundSync,
        onlineChanges: sync.network.onlineChanges,
        isOnline: sync.network.isOnline,
      ),
      cameraPreviewBuilder: (_) => PluginCameraPreview(repository: camera),
    ),
  );
}

/// Removes photo files left behind if the app was killed mid-way through
/// adding a photo or finishing an upload. Housekeeping only: a failure is
/// logged and changes nothing.
Future<void> _deleteOrphanedPhotos(SqfliteUploadQueueRepository queue) async {
  try {
    final removed = await queue.deleteOrphanedPhotos();
    if (removed > 0) {
      developer.log('Removed $removed orphaned photo files', name: 'Startup');
    }
  } on Object catch (error, stack) {
    developer.log(
      'Orphaned photo cleanup failed',
      name: 'Startup',
      error: error,
      stackTrace: stack,
    );
  }
}
