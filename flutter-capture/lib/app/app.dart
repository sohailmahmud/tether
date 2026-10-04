import 'package:flutter/material.dart';

/// Root widget. Feature BLoCs and their dependencies are provided here as the
/// camera and upload-queue features are added.
class TetherCaptureApp extends StatelessWidget {
  const TetherCaptureApp({super.key});

  static const title = 'Tether Capture';

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
      home: const _HomePlaceholder(),
    );
  }
}

class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(TetherCaptureApp.title)),
      body: const Center(child: Text('Camera and upload queue')),
    );
  }
}
