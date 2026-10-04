import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/repositories/camera_repository.dart';
import '../presentation/camera/camera_preview_screen.dart';
import '../presentation/camera/cubit/camera_cubit.dart';

/// Root widget. Dependencies are created in `main.dart` and passed in, so
/// tests can supply fakes.
class TetherCaptureApp extends StatelessWidget {
  const TetherCaptureApp({
    super.key,
    required this.cameraRepository,
    required this.cameraPreviewBuilder,
  });

  static const title = 'Tether Capture';

  final CameraRepository cameraRepository;
  final WidgetBuilder cameraPreviewBuilder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.dark,
        ),
      ),
      home: BlocProvider(
        create: (_) => CameraCubit(cameraRepository),
        child: CameraPreviewScreen(previewBuilder: cameraPreviewBuilder),
      ),
    );
  }
}
