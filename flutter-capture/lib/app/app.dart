import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/datasources/mock_server_settings.dart';
import '../domain/repositories/camera_repository.dart';
import '../domain/repositories/upload_queue_repository.dart';
import '../presentation/camera/camera_preview_screen.dart';
import '../presentation/camera/cubit/camera_cubit.dart';
import '../presentation/uploads/cubit/mock_server_cubit.dart';
import '../presentation/uploads/cubit/sync_cubit.dart';
import '../presentation/uploads/cubit/upload_queue_cubit.dart';

/// Root widget. Dependencies are created in `main.dart` and passed in, so
/// tests can supply fakes.
class TetherCaptureApp extends StatelessWidget {
  const TetherCaptureApp({
    super.key,
    required this.cameraRepository,
    required this.uploadQueueRepository,
    required this.mockServerSettings,
    required this.createSyncCubit,
    required this.cameraPreviewBuilder,
  });

  static const title = 'Tether Capture';

  /// Dark, so the screen around the viewfinder doesn't glare.
  static ThemeData theme() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2563EB),
      brightness: Brightness.dark,
    ),
  );

  final CameraRepository cameraRepository;
  final UploadQueueRepository uploadQueueRepository;
  final MockServerSettings mockServerSettings;
  final SyncCubit Function() createSyncCubit;
  final WidgetBuilder cameraPreviewBuilder;

  @override
  Widget build(BuildContext context) {
    // Provided above the navigator so every screen shares the same cubits.
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => CameraCubit(cameraRepository, uploadQueueRepository),
        ),
        BlocProvider(create: (_) => UploadQueueCubit(uploadQueueRepository)),
        // Not lazy: starts watching connectivity and uploads anything left
        // from last time as soon as the app launches.
        BlocProvider(
          lazy: false,
          create: (_) {
            final cubit = createSyncCubit();
            unawaited(cubit.start());
            return cubit;
          },
        ),
        BlocProvider(
          create: (_) {
            final cubit = MockServerCubit(mockServerSettings);
            unawaited(cubit.load());
            return cubit;
          },
        ),
      ],
      child: MaterialApp(
        title: title,
        debugShowCheckedModeBanner: false,
        theme: theme(),
        home: CameraPreviewScreen(previewBuilder: cameraPreviewBuilder),
      ),
    );
  }
}
