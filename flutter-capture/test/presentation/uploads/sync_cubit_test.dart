import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/domain/entities/upload_queue_snapshot.dart';
import 'package:tether_capture/domain/usecases/process_upload_queue.dart';
import 'package:tether_capture/presentation/uploads/cubit/sync_cubit.dart';

import '../../helpers/fake_upload_api.dart';
import '../../helpers/fake_upload_queue_repository.dart';

void main() {
  late FakeUploadQueueRepository queue;
  late FakeUploadApi api;

  setUp(() {
    queue = FakeUploadQueueRepository(
      UploadQueueSnapshot(batches: [testBatch(id: 'a')]),
    );
    api = FakeUploadApi();
  });

  ProcessUploadQueue engine() => ProcessUploadQueue(queue: queue, api: api);

  blocTest<SyncCubit, SyncState>(
    'shows a run in progress, then its result',
    build: () => SyncCubit(engine()),
    act: (cubit) => cubit.sync(),
    expect: () => [
      const SyncState(isSyncing: true),
      const SyncState(lastRun: UploadRunSummary(uploaded: 1)),
    ],
  );

  blocTest<SyncCubit, SyncState>(
    'Retry now is passed to the engine',
    setUp: () => api.script.addAll([
      FakeUploadApi.serverError,
      FakeUploadApi.serverError,
    ]),
    build: () => SyncCubit(engine()),
    act: (cubit) async {
      await cubit.sync();
      await cubit.sync(retryFailedNow: true);
    },
    verify: (_) => expect(api.uploadedIds, ['a', 'a']),
  );

  blocTest<SyncCubit, SyncState>(
    'an unexpected storage error is reported without crashing',
    setUp: () => queue.claimThrows = StateError('disk I/O error'),
    build: () => SyncCubit(engine()),
    act: (cubit) => cubit.sync(),
    expect: () => [
      const SyncState(isSyncing: true),
      const SyncState(lastRunFailed: true),
    ],
  );
}
