import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/camera_failure.dart';
import 'cubit/camera_cubit.dart';
import 'cubit/camera_state.dart';
import 'viewfinder_math.dart';
import 'widgets/camera_message.dart';
import 'widgets/capture_thumbnail.dart';
import 'widgets/focus_indicator.dart';
import 'widgets/shutter_button.dart';
import 'widgets/zoom_controls.dart';

/// Custom camera: live preview with pinch, slider and button zoom,
/// tap-to-focus, and capture.
///
/// [previewBuilder] renders the live camera image. It is supplied by the app's
/// composition root, so this screen does not depend on the camera plugin and
/// can be widget-tested with a stand-in.
class CameraPreviewScreen extends StatefulWidget {
  const CameraPreviewScreen({super.key, required this.previewBuilder});

  final WidgetBuilder previewBuilder;

  @override
  State<CameraPreviewScreen> createState() => _CameraPreviewScreenState();
}

class _CameraPreviewScreenState extends State<CameraPreviewScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<CameraCubit>();
    _lifecycle = AppLifecycleListener(
      onInactive: () => unawaited(cubit.onAppInactive()),
      onResume: () => unawaited(cubit.onAppResumed()),
    );
    unawaited(cubit.start());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CameraCubit>();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: BlocConsumer<CameraCubit, CameraState>(
          listenWhen: (previous, current) =>
              current is CameraReady &&
              current.captureFailed &&
              !(previous is CameraReady && previous.captureFailed),
          listener: (context, state) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Couldn't take the photo. Please try again."),
              ),
            );
            cubit.captureFailureShown();
          },
          builder: (context, state) => switch (state) {
            CameraReady() => _Viewfinder(
              state: state,
              previewBuilder: widget.previewBuilder,
            ),
            CameraStarting() => const Center(
              child: CircularProgressIndicator(),
            ),
            CameraPaused() => const SizedBox.expand(),
            CameraPermissionRequired(:final permanentlyDenied) => CameraMessage(
              icon: Icons.no_photography_outlined,
              title: 'Camera access needed',
              message: permanentlyDenied
                  ? 'Camera access is turned off for Tether Capture. '
                        'Allow it in Settings to take photos.'
                  : 'Tether Capture needs the camera to take photos for upload.',
              actionLabel: permanentlyDenied ? 'Open settings' : 'Allow camera',
              onAction: permanentlyDenied
                  ? () => unawaited(cubit.openAppSettings())
                  : () => unawaited(cubit.requestPermission()),
            ),
            CameraUnavailable(failure: CameraFailure.noBackCamera) =>
              const CameraMessage(
                icon: Icons.no_photography_outlined,
                title: 'No back camera',
                message: 'This device has no back-facing camera.',
              ),
            CameraUnavailable() => CameraMessage(
              icon: Icons.videocam_off_outlined,
              title: 'Camera unavailable',
              message:
                  "The camera couldn't start. Another app may be using it.",
              actionLabel: 'Try again',
              onAction: () => unawaited(cubit.retry()),
            ),
          },
        ),
      ),
    );
  }
}

class _Viewfinder extends StatefulWidget {
  const _Viewfinder({required this.state, required this.previewBuilder});

  final CameraReady state;
  final WidgetBuilder previewBuilder;

  @override
  State<_Viewfinder> createState() => _ViewfinderState();
}

class _ViewfinderState extends State<_Viewfinder> {
  double _pinchStartZoom = 1;
  Offset? _focusPosition;
  int _focusTaps = 0;

  void _onTapUp(TapUpDetails details, Size previewSize) {
    final cubit = context.read<CameraCubit>();
    if (!widget.state.capabilities.supportsFocusPoint) return;
    final point = normalizedPreviewPoint(details.localPosition, previewSize);
    setState(() {
      _focusPosition = details.localPosition;
      _focusTaps++;
    });
    unawaited(cubit.focusAt(point.dx, point.dy));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CameraCubit>();
    final state = widget.state;
    final capabilities = state.capabilities;
    final canZoom = capabilities.maxZoom > capabilities.minZoom;
    final focusPosition = _focusPosition;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              // The sensor reports a landscape ratio; the UI is portrait.
              aspectRatio: 1 / capabilities.previewAspectRatio,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (_) => _pinchStartZoom = state.zoom,
                      onScaleUpdate: (details) {
                        if (details.pointerCount >= 2) {
                          cubit.setZoom(_pinchStartZoom * details.scale);
                        }
                      },
                      onTapUp: (details) =>
                          _onTapUp(details, constraints.biggest),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          widget.previewBuilder(context),
                          if (focusPosition != null)
                            Positioned(
                              left: focusPosition.dx - FocusIndicator.size / 2,
                              top: focusPosition.dy - FocusIndicator.size / 2,
                              child: FocusIndicator(key: ValueKey(_focusTaps)),
                            ),
                        ],
                      ),
                    ),
                    // Controls sit above the gesture area so their own drags
                    // and taps never reach the pinch and focus handlers.
                    if (canZoom)
                      Positioned(
                        right: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: ZoomSlider(
                            zoom: state.zoom,
                            min: capabilities.minZoom,
                            max: capabilities.maxZoom,
                            onChanged: cubit.setZoom,
                          ),
                        ),
                      ),
                    if (canZoom)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 16,
                        child: Center(
                          child: ZoomPresetButtons(
                            presets: capabilities.zoomPresets,
                            zoom: state.zoom,
                            onSelected: cubit.setZoom,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CaptureThumbnail(
                photo: state.lastCapture,
                count: state.captureCount,
              ),
              ShutterButton(
                enabled: !state.isCapturing,
                onPressed: () => unawaited(cubit.capture()),
              ),
              // Balances the thumbnail so the shutter stays centred.
              const SizedBox.square(dimension: CaptureThumbnail.size),
            ],
          ),
        ),
      ],
    );
  }
}
