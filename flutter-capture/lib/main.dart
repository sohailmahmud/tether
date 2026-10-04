import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'app/app.dart';
import 'app/app_bloc_observer.dart';
import 'app/plugin_camera_preview.dart';
import 'data/datasources/photo_store.dart';
import 'data/datasources/upload_queue_database.dart';
import 'data/repositories/plugin_camera_repository.dart';
import 'data/repositories/sqflite_upload_queue_repository.dart';

/// Composition root: creates the concrete dependencies and starts the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Bloc.observer = const AppBlocObserver();
  // Portrait only: the viewfinder layout and the tap-to-focus mapping assume it.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final documents = await getApplicationDocumentsDirectory();
  final uploadQueue = SqfliteUploadQueueRepository(
    database: await UploadQueueDatabase.open(
      p.join(await getDatabasesPath(), UploadQueueDatabase.fileName),
    ),
    photos: PhotoStore(Directory(p.join(documents.path, 'photos'))),
  );
  final camera = PluginCameraRepository();

  runApp(
    TetherCaptureApp(
      cameraRepository: camera,
      uploadQueueRepository: uploadQueue,
      cameraPreviewBuilder: (_) => PluginCameraPreview(repository: camera),
    ),
  );
}
