import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/domain/entities/captured_photo.dart';
import 'package:tether_capture/domain/entities/upload_queue_snapshot.dart';
import 'package:tether_capture/domain/repositories/upload_queue_repository.dart';
import 'package:tether_capture/presentation/uploads/cubit/upload_queue_cubit.dart';
import 'package:tether_capture/presentation/uploads/cubit/upload_queue_state.dart';

import '../../helpers/fake_upload_queue_repository.dart';

void main() {
  late FakeUploadQueueRepository uploads;

  setUp(() => uploads = FakeUploadQueueRepository());

  final photo = CapturedPhoto(
    path: '/cache/1.jpg',
    capturedAt: DateTime(2026, 10, 4),
  );

  blocTest<UploadQueueCubit, UploadQueueState>(
    'loads the queue from storage',
    setUp: () => uploads.queue = UploadQueueSnapshot(batches: [testBatch()]),
    build: () => UploadQueueCubit(uploads),
    expect: () => [
      UploadQueueState(
        isLoaded: true,
        queue: UploadQueueSnapshot(batches: [testBatch()]),
      ),
    ],
  );

  blocTest<UploadQueueCubit, UploadQueueState>(
    'follows photos added by the camera',
    build: () => UploadQueueCubit(uploads),
    act: (_) => uploads.addToDraft(photo),
    skip: 1,
    verify: (cubit) {
      expect(cubit.state.draftPhotoCount, 1);
      expect(cubit.state.latestDraftPhoto, '/cache/1.jpg');
    },
  );

  blocTest<UploadQueueCubit, UploadQueueState>(
    'submitting moves the draft into the queue',
    build: () => UploadQueueCubit(uploads),
    act: (cubit) async {
      await uploads.addToDraft(photo);
      expect(await cubit.submitDraft(), isTrue);
    },
    verify: (cubit) {
      expect(cubit.state.draftPhotoCount, 0);
      expect(cubit.state.unfinishedBatchCount, 1);
    },
  );

  blocTest<UploadQueueCubit, UploadQueueState>(
    'submitting with nothing captured does nothing',
    build: () => UploadQueueCubit(uploads),
    act: (cubit) async => expect(await cubit.submitDraft(), isFalse),
    expect: () => [const UploadQueueState(isLoaded: true)],
  );

  blocTest<UploadQueueCubit, UploadQueueState>(
    'a failed submit is reported once, then cleared',
    setUp: () => uploads.submitFails = true,
    build: () => UploadQueueCubit(uploads),
    act: (cubit) async {
      await cubit.submitDraft();
      cubit.submitFailureShown();
    },
    expect: () => [
      const UploadQueueState(isLoaded: true),
      const UploadQueueState(isLoaded: true, submitFailed: true),
      const UploadQueueState(isLoaded: true),
    ],
  );

  blocTest<UploadQueueCubit, UploadQueueState>(
    'a storage read failure is reported',
    setUp: () => uploads.readError = const UploadQueueException('unreadable'),
    build: () => UploadQueueCubit(uploads),
    expect: () => [const UploadQueueState(isLoaded: true, loadFailed: true)],
  );
}
