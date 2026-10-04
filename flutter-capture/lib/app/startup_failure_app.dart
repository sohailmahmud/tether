import 'package:flutter/material.dart';

import 'app.dart';

/// Shown instead of the camera when the app can't open its storage (e.g. the
/// device is full). Without storage, photos couldn't be kept safely until
/// they are uploaded, so the app explains rather than starting half-working.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: TetherCaptureApp.title,
      debugShowCheckedModeBanner: false,
      theme: TetherCaptureApp.theme(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Builder(
              builder: (context) {
                final text = Theme.of(context).textTheme;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.sd_card_alert_outlined, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      "Can't open storage",
                      style: text.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tether Capture keeps photos on this device until they '
                      'are uploaded, and couldn\'t open that storage. Free up '
                      'some space, then reopen the app. Nothing has been '
                      'deleted.',
                      style: text.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
