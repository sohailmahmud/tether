import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/domain/entities/retry_policy.dart';
import 'package:tether_capture/domain/entities/upload_queue_snapshot.dart';
import 'package:tether_capture/domain/entities/upload_status.dart';
import 'package:tether_capture/domain/usecases/process_upload_queue.dart';

import '../helpers/fake_upload_api.dart';
import '../helpers/fake_upload_queue_repository.dart';

void main() {
  late FakeUploadQueueRepository queue;
  late FakeUploadApi api;
  late ProcessUploadQueue engine;
  final now = DateTime(2026, 10, 4, 21);

  /// Queue newest first, as the repository returns it.
  void given(List<String> ids) => queue.queue = UploadQueueSnapshot(
    batches: [for (final id in ids.reversed) testBatch(id: id)],
  );

  UploadStatus statusOf(String id) =>
      queue.queue.batches.firstWhere((b) => b.id == id).status;

  setUp(() {
    queue = FakeUploadQueueRepository();
    api = FakeUploadApi();
    engine = ProcessUploadQueue(queue: queue, api: api, clock: () => now);
  });

  test(
    'uploads every pending batch, oldest first, and completes them',
    () async {
      given(['a', 'b', 'c']);

      final summary = await engine();

      expect(api.uploadedIds, ['a', 'b', 'c']);
      expect(summary, const UploadRunSummary(uploaded: 3));
      expect(
        queue.queue.batches.every((b) => b.status == UploadStatus.completed),
        isTrue,
      );
      expect(queue.deletedFiles, [
        'a',
        'b',
        'c',
      ], reason: 'files go only after success');
    },
  );

  test(
    'a failed upload keeps the batch, counts the attempt and schedules a retry',
    () async {
      given(['a']);
      api.script.add(FakeUploadApi.serverError);

      final summary = await engine();

      final batch = queue.queue.batches.single;
      expect(summary, const UploadRunSummary(failed: 1));
      expect(batch.status, UploadStatus.failed);
      expect(batch.retryCount, 1);
      expect(batch.lastError, FakeUploadApi.serverError.message);
      expect(batch.nextAttemptAt, now.add(RetryPolicy.firstDelay));
      expect(batch.items, hasLength(3), reason: 'photos stay queued');
      expect(queue.deletedFiles, isEmpty, reason: 'files are kept');
    },
  );

  test('the backoff grows with each failure of the same batch', () async {
    given(['a']);
    api.script.addAll([FakeUploadApi.serverError, FakeUploadApi.serverError]);

    await engine();
    await engine(retryFailedNow: true);

    final batch = queue.queue.batches.single;
    expect(batch.retryCount, 2);
    expect(batch.nextAttemptAt, now.add(RetryPolicy.delayAfter(2)));
  });

  test(
    'a batch waiting out its backoff is not retried early by a normal run',
    () async {
      given(['a']);
      api.script.add(FakeUploadApi.serverError);
      await engine();

      await engine();

      expect(api.uploadedIds, ['a'], reason: 'still inside its 30 s backoff');
      expect(statusOf('a'), UploadStatus.failed);
    },
  );

  test('Retry now retries failed batches straight away, once each', () async {
    given(['a', 'b']);
    api.script.addAll([FakeUploadApi.serverError, FakeUploadApi.serverError]);
    await engine();
    api.script.add(FakeUploadApi.serverError);

    final summary = await engine(retryFailedNow: true);

    expect(api.uploadedIds, [
      'a',
      'b',
      'a',
      'b',
    ], reason: 'no endless loop on repeated failure');
    expect(summary, const UploadRunSummary(uploaded: 1, failed: 1));
    expect(statusOf('a'), UploadStatus.failed);
    expect(statusOf('b'), UploadStatus.completed);
  });

  test(
    'no connection stops the run; the other batches wait untouched',
    () async {
      given(['a', 'b', 'c']);
      api.script.add(FakeUploadApi.noConnection);

      final summary = await engine();

      expect(api.uploadedIds, ['a']);
      expect(summary, const UploadRunSummary(failed: 1, stoppedOffline: true));
      expect(statusOf('b'), UploadStatus.pending);
      expect(statusOf('c'), UploadStatus.pending);
    },
  );

  test(
    'an unexpected API error still records a failure instead of losing the batch',
    () async {
      given(['a']);
      api.throws = StateError('bug in the HTTP client');

      final summary = await engine();

      expect(summary, const UploadRunSummary(failed: 1));
      expect(statusOf('a'), UploadStatus.failed);
      expect(queue.queue.batches.single.lastError, contains('unexpectedly'));
    },
  );

  test(
    'overlapping triggers share one run and never upload a batch twice',
    () async {
      given(['a', 'b']);
      api.gate = Completer<void>();

      final first = engine();
      final second = engine();
      final third = engine();
      api.gate!.complete();
      final summaries = await Future.wait([first, second, third]);

      expect(api.uploadedIds, ['a', 'b']);
      expect(summaries.toSet(), {const UploadRunSummary(uploaded: 2)});
    },
  );

  test(
    'a batch submitted during a run is picked up before the run ends',
    () async {
      given(['a']);
      api.gate = Completer<void>();
      final run = engine();
      await Future<void>.delayed(Duration.zero);

      // Submitted while "a" is uploading, then the submit triggers the engine.
      queue.queue = UploadQueueSnapshot(
        batches: [
          testBatch(id: 'b'),
          ...queue.queue.batches,
        ],
      );
      final joined = engine();
      api.gate!.complete();

      expect(await run, const UploadRunSummary(uploaded: 2));
      expect(await joined, const UploadRunSummary(uploaded: 2));
      expect(api.uploadedIds, ['a', 'b']);
    },
  );

  test(
    'each run first recovers uploads abandoned longer than the lease',
    () async {
      await engine();

      expect(queue.lastRecoveryCutoff, now.subtract(RetryPolicy.uploadLease));
    },
  );
}
