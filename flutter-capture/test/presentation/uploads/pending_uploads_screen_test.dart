import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/domain/entities/upload_queue_snapshot.dart';
import 'package:tether_capture/domain/entities/upload_status.dart';
import 'package:tether_capture/presentation/uploads/cubit/upload_queue_cubit.dart';
import 'package:tether_capture/presentation/uploads/pending_uploads_screen.dart';

import '../../helpers/fake_upload_queue_repository.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    UploadQueueSnapshot queue,
  ) async {
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => UploadQueueCubit(FakeUploadQueueRepository(queue)),
        child: const MaterialApp(home: PendingUploadsScreen()),
      ),
    );
    await tester.pump();
  }

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
            lastError: 'No internet connection',
          ),
          testBatch(id: 'c', photos: 1, status: UploadStatus.completed),
        ],
      ),
    );

    expect(find.text('2 BATCHES · 9 PHOTOS WAITING'), findsOneWidget);
    expect(find.text('2 photos'), findsOneWidget);
    expect(find.text('Waiting to upload'), findsOneWidget);
    expect(find.text('7 photos'), findsOneWidget);
    expect(find.text('Failed 2× · will retry'), findsOneWidget);
    expect(find.text('No internet connection'), findsOneWidget);
    expect(find.text('1 photo'), findsOneWidget);
    expect(find.text('Uploaded'), findsOneWidget);
    expect(
      find.text('+2'),
      findsOneWidget,
      reason: '7 photos: 5 thumbnails, then +2',
    );
  });

  testWidgets('Start new upload batch goes back to the camera', (tester) async {
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => UploadQueueCubit(FakeUploadQueueRepository()),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PendingUploadsScreen(),
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
