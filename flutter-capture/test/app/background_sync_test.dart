import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/app/background_sync.dart';
import 'package:tether_capture/domain/entities/upload_queue_snapshot.dart';
import 'package:tether_capture/domain/entities/upload_status.dart';
import 'package:tether_capture/domain/usecases/process_upload_queue.dart';

import '../helpers/fake_upload_api.dart';
import '../helpers/fake_upload_queue_repository.dart';

void main() {
  late FakeUploadQueueRepository queue;
  late FakeUploadApi api;

  setUp(() {
    queue = FakeUploadQueueRepository();
    api = FakeUploadApi();
  });

  Future<bool> run() =>
      runBackgroundSync(ProcessUploadQueue(queue: queue, api: api), queue);

  test('reports done once everything is uploaded', () async {
    queue.queue = UploadQueueSnapshot(
      batches: [
        testBatch(id: 'a'),
        testBatch(id: 'b'),
      ],
    );

    expect(await run(), isTrue);
    expect(api.uploadedIds, ['b', 'a']);
  });

  test('asks WorkManager to retry later while anything is left', () async {
    queue.queue = UploadQueueSnapshot(batches: [testBatch(id: 'a')]);
    api.script.add(FakeUploadApi.noConnection);

    expect(await run(), isFalse);
    expect(queue.queue.batches.single.status, UploadStatus.failed);
    expect(
      queue.queue.batches.single.items,
      hasLength(3),
      reason: 'photos kept',
    );
  });

  test(
    "retries failed batches without waiting for the app's backoff",
    () async {
      queue.queue = UploadQueueSnapshot(
        batches: [
          testBatch(
            id: 'f',
            status: UploadStatus.failed,
            retryCount: 2,
          ).copyWithNextAttempt(
            DateTime.now().add(const Duration(minutes: 10)),
          ),
        ],
      );

      expect(await run(), isTrue);
      expect(api.uploadedIds, ['f']);
    },
  );
}
