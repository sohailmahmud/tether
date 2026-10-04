import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:workmanager/workmanager.dart';

import 'app/app.dart';
import 'app/app_bloc_observer.dart';
import 'app/background_sync.dart';
import 'app/plugin_camera_preview.dart';
import 'app/queue_change_channel.dart';
import 'app/sync_dependencies.dart';
import 'data/datasources/workmanager_sync_scheduler.dart';
import 'data/repositories/plugin_camera_repository.dart';
import 'presentation/uploads/cubit/sync_cubit.dart';

/// Composition root: creates the concrete dependencies and starts the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Bloc.observer = const AppBlocObserver();
  // Portrait only: the viewfinder layout and the tap-to-focus mapping assume it.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // The same engine setup the background worker builds in its own isolate.
  final sync = await SyncDependencies.open();
  // Uploads done by the background worker reach open screens through this.
  QueueChangeChannel.listen(sync.uploadQueue.notifyExternalChange);
  await Workmanager().initialize(backgroundSyncDispatcher);
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
