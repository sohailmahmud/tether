import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/app/app.dart';
import 'package:tether_capture/data/datasources/mock_server_settings.dart';
import 'package:tether_capture/domain/entities/upload_status.dart';
import 'package:tether_capture/domain/usecases/process_upload_queue.dart';
import 'package:tether_capture/presentation/uploads/cubit/sync_cubit.dart';

import '../helpers/fake_background_sync_scheduler.dart';
import '../helpers/fake_camera_repository.dart';
import '../helpers/fake_upload_api.dart';
import '../helpers/fake_upload_queue_repository.dart';

/// End-to-end user flows through the real app shell: [TetherCaptureApp] with
/// its providers, navigation, both screens, every Cubit and the upload engine.
/// Only the edges are faked: camera hardware, the network and the queue's
/// storage. The engine and Cubits read the test's virtual clock, so retry
/// timing is exact.
void main() {
  late FakeCameraRepository camera;
  late FakeUploadQueueRepository queue;
  late FakeUploadApi api;
  late FakeBackgroundSyncScheduler background;
  late StreamController<bool> connectivity;

  setUp(() {
    camera = FakeCameraRepository();
    queue = FakeUploadQueueRepository();
    api = FakeUploadApi();
    background = FakeBackgroundSyncScheduler();
    connectivity = StreamController<bool>.broadcast();
  });

  tearDown(() => connectivity.close());

  Future<void> launch(WidgetTester tester) async {
    // A phone-sized portrait screen.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    DateTime now() => tester.binding.clock.now();
    await tester.pumpWidget(
      TetherCaptureApp(
        cameraRepository: camera,
        uploadQueueRepository: queue,
        mockServerSettings: MockServerSettings(File('/nonexistent/mode.txt')),
        createSyncCubit: () => SyncCubit(
          processQueue: ProcessUploadQueue(queue: queue, api: api, clock: now),
          queue: queue,
          backgroundSync: background,
          onlineChanges: connectivity.stream,
          isOnline: () async => true,
          clock: now,
        ),
        cameraPreviewBuilder: (_) => const ColoredBox(color: Colors.grey),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> takePhotos(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await tester.tap(find.bySemanticsLabel('Take photo'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> uploadBatch(WidgetTester tester, int photos) async {
    await tester.tap(find.text('Upload batch ($photos)'));
    await tester.pumpAndSettle();
  }

  Future<void> setOnline(WidgetTester tester, bool online) async {
    connectivity.add(online);
    // One frame delivers the event to SyncCubit, the next shows its new state.
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'capture a batch, upload it, and come back to a reopened camera',
    (tester) async {
      await launch(tester);
      expect(camera.isOpen, isTrue);

      await takePhotos(tester, 2);
      expect(find.bySemanticsLabel('2 photos in this batch'), findsOneWidget);
      await uploadBatch(tester, 2);

      expect(find.text('Upload Manager'), findsOneWidget);
      expect(find.text('2 photos'), findsOneWidget);
      expect(find.text('Uploaded'), findsOneWidget);
      expect(find.text('ALL BATCHES UPLOADED'), findsOneWidget);
      expect(api.uploadedIds, hasLength(1));
      expect(queue.deletedFiles, hasLength(1), reason: 'files go after upload');
      expect(camera.isOpen, isFalse, reason: 'released while covered');

      await tester.tap(find.text('Start new upload batch'));
      await tester.pumpAndSettle();

      expect(camera.isOpen, isTrue, reason: 'reopened on return');
      expect(
        find.text('Upload batch'),
        findsOneWidget,
        reason: 'new empty batch',
      );
    },
  );

  testWidgets(
    'no internet: the batch stays queued, then uploads by itself once the '
    'connection is back and stable',
    (tester) async {
      api.script.add(FakeUploadApi.noConnection);
      await launch(tester);
      await takePhotos(tester, 1);
      await uploadBatch(tester, 1);

      expect(find.text('Failed once'), findsOneWidget);
      expect(find.text('No internet connection.'), findsOneWidget);
      expect(queue.deletedFiles, isEmpty, reason: 'photos stay on the device');
      expect(background.scheduleCount, greaterThan(0), reason: 'worker armed');

      await setOnline(tester, false);
      expect(find.textContaining("You're offline"), findsOneWidget);

      await setOnline(tester, true);
      await tester.pump(const Duration(seconds: 2));
      expect(
        api.uploadedIds,
        hasLength(1),
        reason: 'waits for a stable connection',
      );

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(api.uploadedIds, hasLength(2));
      expect(find.text('Uploaded'), findsOneWidget);
      expect(find.textContaining("You're offline"), findsNothing);
      expect(queue.queue.batches.single.status, UploadStatus.completed);
    },
  );

  testWidgets(
    'server error: the batch is retried automatically when its backoff ends',
    (tester) async {
      api.script.add(FakeUploadApi.serverError);
      await launch(tester);
      await takePhotos(tester, 1);
      await uploadBatch(tester, 1);

      expect(find.text('Failed once'), findsOneWidget);
      expect(find.text('Server error (503).'), findsOneWidget);
      expect(find.text('Retry now'), findsOneWidget);

      await tester.pump(const Duration(seconds: 29));
      expect(api.uploadedIds, hasLength(1), reason: 'still backing off');

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(api.uploadedIds, hasLength(2));
      expect(find.text('Uploaded'), findsOneWidget);
    },
  );

  testWidgets('Retry now skips the backoff', (tester) async {
    api.script.add(FakeUploadApi.serverError);
    await launch(tester);
    await takePhotos(tester, 1);
    await uploadBatch(tester, 1);
    expect(find.text('Failed once'), findsOneWidget);

    await tester.tap(find.text('Retry now'));
    await tester.pumpAndSettle();

    expect(api.uploadedIds, hasLength(2));
    expect(find.text('Uploaded'), findsOneWidget);
  });

  testWidgets('photos taken after an upload start a separate batch', (
    tester,
  ) async {
    await launch(tester);
    await takePhotos(tester, 2);
    await uploadBatch(tester, 2);
    await tester.tap(find.text('Start new upload batch'));
    await tester.pumpAndSettle();

    await takePhotos(tester, 3);
    await uploadBatch(tester, 3);

    expect(find.text('3 photos'), findsOneWidget);
    expect(find.text('2 photos'), findsOneWidget);
    expect(find.text('Uploaded'), findsNWidgets(2));
    expect(api.uploadedIds.toSet(), hasLength(2));
  });
}
