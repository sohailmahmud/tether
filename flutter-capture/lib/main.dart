import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app/app.dart';
import 'app/app_bloc_observer.dart';
import 'app/plugin_camera_preview.dart';
import 'data/repositories/plugin_camera_repository.dart';

/// Composition root: creates the concrete dependencies and starts the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Bloc.observer = const AppBlocObserver();
  // Portrait only: the viewfinder layout and the tap-to-focus mapping assume it.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final camera = PluginCameraRepository();
  runApp(
    TetherCaptureApp(
      cameraRepository: camera,
      cameraPreviewBuilder: (_) => PluginCameraPreview(repository: camera),
    ),
  );
}
