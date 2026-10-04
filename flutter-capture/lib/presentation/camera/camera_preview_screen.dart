import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/camera_failure.dart';
import '../uploads/cubit/sync_cubit.dart';
import '../uploads/cubit/upload_queue_cubit.dart';
import '../uploads/cubit/upload_queue_state.dart';
import '../uploads/pending_uploads_screen.dart';
import 'cubit/camera_cubit.dart';
import 'cubit/camera_state.dart';
import 'viewfinder_math.dart';
import 'widgets/camera_message.dart';
import 'widgets/capture_thumbnail.dart';
import 'widgets/focus_indicator.dart';
import 'widgets/shutter_button.dart';
import 'widgets/zoom_controls.dart';

/// Custom camera: live preview with pinch, slider and button zoom,
/// tap-to-focus, and capture into the batch being built.
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

  /// Opens Pending Uploads, releasing the camera while it is covered.
  Future<void> _openPendingUploads() async {
    final camera = context.read<CameraCubit>();
    unawaited(camera.onScreenHidden());
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PendingUploadsScreen()),
    );
    unawaited(camera.onScreenShown());
  }

  /// "Upload batch": queues the photos taken so far, starts uploading, and
  /// shows the queue.
  Future<void> _uploadBatch() async {
    final sync = context.read<SyncCubit>();
    final submitted = await context.read<UploadQueueCubit>().submitDraft();
    if (!submitted) return;
    unawaited(sync.sync());
    if (mounted) await _openPendingUploads();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: MultiBlocListener(
          listeners: [
            BlocListener<CameraCubit, CameraState>(
              listenWhen: (previous, current) =>
                  current is CameraReady &&
                  current.captureFailed &&
                  !(previous is CameraReady && previous.captureFailed),
              listener: (context, _) {
                _showError(
                  context,
                  "Couldn't take the photo. Please try again.",
                );
                context.read<CameraCubit>().captureFailureShown();
              },
            ),
            BlocListener<UploadQueueCubit, UploadQueueState>(
              listenWhen: (previous, current) =>
                  current.submitFailed && !previous.submitFailed,
              listener: (context, _) {
                _showError(
                  context,
                  "Couldn't queue the batch. Please try again.",
                );
                context.read<UploadQueueCubit>().submitFailureShown();
              },
            ),
          ],
          child: Column(
            children: [
              Expanded(
                child: BlocBuilder<CameraCubit, CameraState>(
                  builder: (context, state) => _CameraArea(
                    state: state,
                    previewBuilder: widget.previewBuilder,
                  ),
                ),
              ),
              _CaptureControls(
                onOpenPendingUploads: () => unawaited(_openPendingUploads()),
                onUploadBatch: () => unawaited(_uploadBatch()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The viewfinder, or an explanation when the camera can't be shown.
class _CameraArea extends StatelessWidget {
  const _CameraArea({required this.state, required this.previewBuilder});

  final CameraState state;
  final WidgetBuilder previewBuilder;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CameraCubit>();
    return switch (state) {
      final CameraReady ready => _Viewfinder(
        state: ready,
        previewBuilder: previewBuilder,
      ),
      CameraStarting() => const Center(child: CircularProgressIndicator()),
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
        message: "The camera couldn't start. Another app may be using it.",
        actionLabel: 'Try again',
        onAction: () => unawaited(cubit.retry()),
      ),
    };
  }
}

/// Thumbnail and count of the batch being built, the shutter, the way to the
/// queue, and "Upload batch". Shown in every camera state, so queued uploads
/// stay reachable even when the camera can't be used.
class _CaptureControls extends StatelessWidget {
  const _CaptureControls({
    required this.onOpenPendingUploads,
    required this.onUploadBatch,
  });

  final VoidCallback onOpenPendingUploads;
  final VoidCallback onUploadBatch;

  @override
  Widget build(BuildContext context) {
    final camera = context.watch<CameraCubit>().state;
    final queue = context.watch<UploadQueueCubit>().state;
    final canCapture = camera is CameraReady && !camera.isCapturing;
    final draftCount = queue.draftPhotoCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CaptureThumbnail(
                imagePath: queue.latestDraftPhoto,
                count: draftCount,
              ),
              ShutterButton(
                enabled: canCapture,
                onPressed: () =>
                    unawaited(context.read<CameraCubit>().capture()),
              ),
              _PendingUploadsButton(
                count: queue.unfinishedBatchCount,
                onPressed: onOpenPendingUploads,
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: draftCount > 0 ? onUploadBatch : null,
            icon: const Icon(Icons.upload),
            label: Text(
              draftCount > 0 ? 'Upload batch ($draftCount)' : 'Upload batch',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingUploadsButton extends StatelessWidget {
  const _PendingUploadsButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: count == 0
          ? 'Pending uploads'
          : 'Pending uploads, ${count == 1 ? '1 batch' : '$count batches'} waiting',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: CaptureThumbnail.size,
        child: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: IconButton.filledTonal(
            onPressed: onPressed,
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
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
    if (!widget.state.capabilities.supportsFocusPoint) return;
    final point = normalizedPreviewPoint(details.localPosition, previewSize);
    setState(() {
      _focusPosition = details.localPosition;
      _focusTaps++;
    });
    unawaited(context.read<CameraCubit>().focusAt(point.dx, point.dy));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CameraCubit>();
    final state = widget.state;
    final capabilities = state.capabilities;
    final canZoom = capabilities.maxZoom > capabilities.minZoom;
    final focusPosition = _focusPosition;

    return Center(
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
                onTapUp: (details) => _onTapUp(details, constraints.biggest),
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
              // Controls sit above the gesture area so their own drags and
              // taps never reach the pinch and focus handlers.
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
    );
  }
}
