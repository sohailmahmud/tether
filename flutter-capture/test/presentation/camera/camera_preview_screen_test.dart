import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/data/datasources/mock_server_settings.dart';
import 'package:tether_capture/domain/entities/camera_capabilities.dart';
import 'package:tether_capture/domain/entities/camera_failure.dart';
import 'package:tether_capture/domain/repositories/camera_repository.dart';
import 'package:tether_capture/domain/usecases/process_upload_queue.dart';
import 'package:tether_capture/presentation/camera/camera_preview_screen.dart';
import 'package:tether_capture/presentation/camera/cubit/camera_cubit.dart';
import 'package:tether_capture/presentation/camera/cubit/camera_state.dart';
import 'package:tether_capture/presentation/camera/widgets/focus_indicator.dart';
import 'package:tether_capture/presentation/uploads/cubit/mock_server_cubit.dart';
import 'package:tether_capture/presentation/uploads/cubit/sync_cubit.dart';
import 'package:tether_capture/presentation/uploads/cubit/upload_queue_cubit.dart';
import 'package:tether_capture/presentation/uploads/pending_uploads_screen.dart';

import '../../helpers/fake_background_sync_scheduler.dart';
import '../../helpers/fake_camera_repository.dart';
import '../../helpers/fake_upload_api.dart';
import '../../helpers/fake_upload_queue_repository.dart';

const _previewKey = Key('preview');

void main() {
  late FakeCameraRepository camera;
  late FakeUploadQueueRepository uploads;
  late FakeUploadApi api;
  late CameraCubit cubit;

  setUp(() {
    camera = FakeCameraRepository();
    uploads = FakeUploadQueueRepository();
    // Uploads hang, so a submitted batch stays visibly "uploading".
    api = FakeUploadApi()..gate = Completer<void>();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    // A phone-sized portrait screen.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      // As in the app: providers above the navigator, so pushed screens share
      // them. They also own and close the cubits; closing from addTearDown
      // would hang, because teardown runs after fake time stops.
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => cubit = CameraCubit(camera, uploads)),
          BlocProvider(create: (_) => UploadQueueCubit(uploads)),
          BlocProvider(
            create: (_) => SyncCubit(
              processQueue: ProcessUploadQueue(queue: uploads, api: api),
              queue: uploads,
              backgroundSync: FakeBackgroundSyncScheduler(),
              onlineChanges: const Stream.empty(),
              isOnline: () async => true,
            ),
          ),
          BlocProvider(
            create: (_) => MockServerCubit(
              MockServerSettings(File('/nonexistent/mode.txt')),
            ),
          ),
        ],
        child: MaterialApp(
          home: CameraPreviewScreen(
            previewBuilder: (_) =>
                const ColoredBox(key: _previewKey, color: Colors.grey),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double zoom() => (cubit.state as CameraReady).zoom;

  group('viewfinder', () {
    testWidgets(
      'shows the preview with buttons for the zoom levels this camera has',
      (tester) async {
        await pumpScreen(tester);

        expect(find.byKey(_previewKey), findsOneWidget);
        expect(find.bySemanticsLabel('Zoom 1x'), findsOneWidget);
        expect(find.bySemanticsLabel('Zoom 2x'), findsOneWidget);
        expect(find.bySemanticsLabel('Zoom 5x'), findsOneWidget);
        expect(find.bySemanticsLabel('Zoom 0.5x'), findsNothing);
        expect(find.byType(Slider), findsOneWidget);
      },
    );

    testWidgets('a camera with an ultra-wide lens gets a 0.5x button', (
      tester,
    ) async {
      camera.capabilities = const CameraCapabilities(
        minZoom: 0.5,
        maxZoom: 10,
        supportsFocusPoint: true,
        previewAspectRatio: 4 / 3,
      );
      await pumpScreen(tester);

      await tester.tap(find.bySemanticsLabel('Zoom 0.5x'));
      await tester.pump();

      expect(zoom(), 0.5);
      expect(camera.zoomCalls.last, 0.5);
    });

    testWidgets('a zoom button jumps to its level', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.bySemanticsLabel('Zoom 2x'));
      await tester.pump();

      expect(zoom(), 2);
      expect(camera.zoomCalls, [2]);
    });

    testWidgets('dragging the slider up zooms in', (tester) async {
      await pumpScreen(tester);

      await tester.drag(find.byType(Slider), const Offset(0, -150));
      await tester.pump();

      expect(zoom(), greaterThan(1));
    });

    // Two fingers moving in small alternating steps, as a real pinch does.
    Future<void> pinch(WidgetTester tester, {required double by}) async {
      final center = tester.getCenter(find.byKey(_previewKey));
      final left = await tester.startGesture(center - const Offset(60, 0));
      final right = await tester.startGesture(
        center + const Offset(60, 0),
        pointer: 2,
      );
      for (var i = 0; i < 10; i++) {
        await left.moveBy(Offset(-by / 20, 0));
        await right.moveBy(Offset(by / 20, 0));
        await tester.pump();
      }
      await left.up();
      await right.up();
    }

    testWidgets('pinching out zooms in, pinching in zooms out', (tester) async {
      await pumpScreen(tester);

      await pinch(tester, by: 120);
      final zoomedIn = zoom();
      expect(zoomedIn, greaterThan(1.3));

      await pinch(tester, by: -80);
      expect(zoom(), lessThan(zoomedIn));
    });

    testWidgets('tapping the preview focuses there and shows the indicator', (
      tester,
    ) async {
      await pumpScreen(tester);
      final preview = tester.getRect(find.byKey(_previewKey));

      await tester.tapAt(
        preview.topLeft + Offset(preview.width * 0.25, preview.height * 0.75),
      );
      await tester.pump();

      expect(find.byType(FocusIndicator), findsOneWidget);
      final (x, y) = camera.focusCalls.single;
      expect(x, closeTo(0.25, 0.01));
      expect(y, closeTo(0.75, 0.01));
      await tester.pumpAndSettle();
    });

    testWidgets('the shutter adds photos to the batch being built', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Upload batch'),
            )
            .onPressed,
        isNull,
        reason: 'nothing to upload yet',
      );

      await tester.tap(find.bySemanticsLabel('Take photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Take photo'));
      await tester.pumpAndSettle();

      expect(camera.captureCount, 2);
      expect(uploads.queue.draft!.photoCount, 2);
      expect(find.bySemanticsLabel('2 photos in this batch'), findsOneWidget);
      expect(find.text('Upload batch (2)'), findsOneWidget);
    });

    testWidgets(
      'Upload batch queues the photos, starts uploading, shows Pending Uploads, '
      'and the camera reopens on return',
      (tester) async {
        await pumpScreen(tester);
        await tester.tap(find.bySemanticsLabel('Take photo'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Upload batch (1)'));
        // Not pumpAndSettle: the upload's progress bars animate until it ends.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(PendingUploadsScreen), findsOneWidget);
        expect(find.text('Uploading'), findsOneWidget);
        expect(api.uploadedIds, hasLength(1));
        expect(camera.isOpen, isFalse, reason: 'released while covered');

        await tester.tap(find.text('Start new upload batch'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byKey(_previewKey), findsOneWidget);
        expect(camera.openCount, 2);
        expect(
          find.text('Upload batch'),
          findsOneWidget,
          reason: 'a fresh batch',
        );
        expect(
          find.bySemanticsLabel('Pending uploads, 1 batch waiting'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a photo that cannot be queued is reported', (tester) async {
      uploads.addFails = true;
      await pumpScreen(tester);

      await tester.tap(find.bySemanticsLabel('Take photo'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text("Couldn't take the photo. Please try again."),
        findsOneWidget,
      );
    });

    testWidgets('a failed capture is reported', (tester) async {
      camera.captureFails = true;
      await pumpScreen(tester);

      await tester.tap(find.bySemanticsLabel('Take photo'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text("Couldn't take the photo. Please try again."),
        findsOneWidget,
      );
    });
  });

  group('when the camera cannot be used', () {
    testWidgets('denied permission offers to ask again', (tester) async {
      camera
        ..status = CameraPermission.denied
        ..requestResult = CameraPermission.denied;
      await pumpScreen(tester);
      expect(find.byKey(_previewKey), findsNothing);

      camera.requestResult = CameraPermission.granted;
      await tester.tap(find.text('Allow camera'));
      await tester.pumpAndSettle();

      expect(camera.requestCount, 2);
      expect(find.byKey(_previewKey), findsOneWidget);
    });

    testWidgets('permission turned off for good points to Settings', (
      tester,
    ) async {
      camera
        ..status = CameraPermission.denied
        ..requestResult = CameraPermission.permanentlyDenied;
      await pumpScreen(tester);

      await tester.tap(find.text('Open settings'));

      expect(camera.settingsOpened, isTrue);
    });

    testWidgets('a camera that fails to start can be retried', (tester) async {
      camera.openFailure = CameraFailure.initializationFailed;
      await pumpScreen(tester);
      expect(find.text('Camera unavailable'), findsOneWidget);

      camera.openFailure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.byKey(_previewKey), findsOneWidget);
    });

    testWidgets('a device without a back camera says so', (tester) async {
      camera.openFailure = CameraFailure.noBackCamera;
      await pumpScreen(tester);

      expect(find.text('No back camera'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });
  });
}
