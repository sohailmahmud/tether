import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/data/datasources/mock_server_settings.dart';
import 'package:tether_capture/domain/entities/upload_queue_snapshot.dart';
import 'package:tether_capture/domain/entities/upload_status.dart';
import 'package:tether_capture/domain/usecases/process_upload_queue.dart';
import 'package:tether_capture/presentation/uploads/cubit/mock_server_cubit.dart';
import 'package:tether_capture/presentation/uploads/cubit/sync_cubit.dart';
import 'package:tether_capture/presentation/uploads/cubit/upload_queue_cubit.dart';
import 'package:tether_capture/presentation/uploads/pending_uploads_screen.dart';

import '../../helpers/fake_background_sync_scheduler.dart';
import '../../helpers/fake_upload_api.dart';
import '../../helpers/fake_upload_queue_repository.dart';

void main() {
  late FakeUploadQueueRepository uploads;
  late FakeUploadApi api;

  Widget providers(Widget child) => MultiBlocProvider(
    providers: [
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
        create: (_) =>
            MockServerCubit(MockServerSettings(File('/nonexistent/mode.txt'))),
      ),
    ],
    child: child,
  );

  Future<void> pumpScreen(
    WidgetTester tester,
    UploadQueueSnapshot queue,
  ) async {
    // A phone-sized portrait screen.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    uploads = FakeUploadQueueRepository(queue);
    await tester.pumpWidget(
      providers(const MaterialApp(home: PendingUploadsScreen())),
    );
    await tester.pump();
  }

  setUp(() => api = FakeUploadApi());

  testWidgets('an empty queue says so', (tester) async {
    await pumpScreen(tester, const UploadQueueSnapshot());

    expect(find.textContaining('No pending uploads'), findsOneWidget);
  });

  testWidgets('lists each batch with its photo count and status', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      UploadQueueSnapshot(
        batches: [
          testBatch(id: 'a', photos: 2),
          testBatch(
            id: 'b',
            photos: 7,
            status: UploadStatus.failed,
            retryCount: 2,
            lastError: 'No internet connection.',
          ),
          testBatch(id: 'c', photos: 1, status: UploadStatus.completed),
          testBatch(id: 'd', photos: 1, status: UploadStatus.uploading),
        ],
      ),
    );

    expect(find.text('3 BATCHES · 10 PHOTOS WAITING'), findsOneWidget);
    expect(find.text('Waiting to upload'), findsOneWidget);
    expect(find.text('Failed 2×'), findsOneWidget);
    expect(find.text('No internet connection.'), findsOneWidget);
    expect(find.text('Retrying as soon as possible.'), findsOneWidget);
    expect(
      find.text('+3'),
      findsOneWidget,
      reason: '7 photos on a phone-width card: 4 thumbnails, then +3',
    );
    // The last cards are below the fold; scroll to them as a user would.
    await tester.scrollUntilVisible(find.text('Uploading'), 300);
    expect(find.text('Uploaded'), findsOneWidget);
    expect(
      find.text('Stored on the server; removed from this device.'),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('Retry now appears only for failed batches and uploads them', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      UploadQueueSnapshot(
        batches: [
          testBatch(
            id: 'f',
            status: UploadStatus.failed,
            retryCount: 1,
            lastError: 'Timed out.',
          ).copyWithNextAttempt(
            DateTime.now().add(const Duration(minutes: 10)),
          ),
        ],
      ),
    );

    await tester.tap(find.text('Retry now'));
    await tester.pumpAndSettle();

    expect(api.uploadedIds, [
      'f',
    ], reason: 'retried despite its 10-minute backoff');
    expect(find.text('Uploaded'), findsOneWidget);
    expect(find.text('Retry now'), findsNothing);
  });

  testWidgets('the mock server mode can be changed from the screen', (
    tester,
  ) async {
    await pumpScreen(tester, const UploadQueueSnapshot());
    expect(find.text('Normal'), findsOneWidget);

    await tester.tap(find.text('Normal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Server error'));
    await tester.pumpAndSettle();

    expect(
      find.text('Server error'),
      findsOneWidget,
      reason: 'shown in the app bar',
    );
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('the app bar names the mode briefly, so the title has room', (
    tester,
  ) async {
    await pumpScreen(tester, const UploadQueueSnapshot());

    await tester.tap(find.byIcon(Icons.dns_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slow connection'));
    await tester.pumpAndSettle();

    final appBar = find.byType(AppBar);
    expect(
      find.descendant(of: appBar, matching: find.text('Slow')),
      findsOneWidget,
    );
    expect(find.byTooltip('Mock server: Slow connection'), findsOneWidget);
  });

  testWidgets('offline, it says uploads will resume by themselves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    uploads = FakeUploadQueueRepository();
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => UploadQueueCubit(uploads)),
          BlocProvider(
            create: (_) {
              final cubit = SyncCubit(
                processQueue: ProcessUploadQueue(queue: uploads, api: api),
                queue: uploads,
                backgroundSync: FakeBackgroundSyncScheduler(),
                onlineChanges: const Stream.empty(),
                isOnline: () async => false,
              );
              unawaited(cubit.start());
              return cubit;
            },
          ),
          BlocProvider(
            create: (_) => MockServerCubit(
              MockServerSettings(File('/nonexistent/mode.txt')),
            ),
          ),
        ],
        child: const MaterialApp(home: PendingUploadsScreen()),
      ),
    );
    await tester.pump();

    expect(find.textContaining("You're offline"), findsOneWidget);
  });

  testWidgets('Start new upload batch goes back to the camera', (tester) async {
    uploads = FakeUploadQueueRepository();
    await tester.pumpWidget(
      providers(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PendingUploadsScreen(),
                  ),
                ),
              ),
              child: const Text('camera'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('camera'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start new upload batch'));
    await tester.pumpAndSettle();

    expect(find.byType(PendingUploadsScreen), findsNothing);
    expect(find.text('camera'), findsOneWidget);
  });
}
