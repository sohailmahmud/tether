import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/domain/entities/upload_queue_snapshot.dart';
import 'package:tether_capture/domain/entities/upload_status.dart';
import 'package:tether_capture/domain/repositories/upload_queue_repository.dart';
import 'package:tether_capture/domain/usecases/process_upload_queue.dart';
import 'package:tether_capture/presentation/uploads/cubit/sync_cubit.dart';

import '../../helpers/fake_background_sync_scheduler.dart';
import '../../helpers/fake_upload_api.dart';
import '../../helpers/fake_upload_queue_repository.dart';

void main() {
  final launch = DateTime(2026, 10, 4, 21);
  late FakeUploadQueueRepository queue;
  late FakeUploadApi api;
  late FakeBackgroundSyncScheduler background;
  late StreamController<bool> connectivity;

  setUp(() {
    queue = FakeUploadQueueRepository();
    api = FakeUploadApi();
    background = FakeBackgroundSyncScheduler();
    connectivity = StreamController<bool>.broadcast();
  });

  tearDown(() => connectivity.close());

  /// Runs [body] in virtual time with a started cubit.
  void withCubit(
    void Function(FakeAsync async, SyncCubit cubit) body, {
    bool onlineAtLaunch = true,
    void Function()? beforeStart,
  }) {
    fakeAsync((async) {
      // Inside the fake zone, so futures it creates (e.g. gates) resume here.
      beforeStart?.call();
      DateTime now() => launch.add(async.elapsed);
      final cubit = SyncCubit(
        processQueue: ProcessUploadQueue(queue: queue, api: api, clock: now),
        queue: queue,
        backgroundSync: background,
        onlineChanges: connectivity.stream,
        isOnline: () async => onlineAtLaunch,
        clock: now,
      );
      unawaited(cubit.start());
      async.flushMicrotasks();
      body(async, cubit);
      unawaited(cubit.close());
      async.flushMicrotasks();
    });
  }

  void goOnline(FakeAsync async, bool online) {
    connectivity.add(online);
    async.flushMicrotasks();
  }

  test(
    'on launch it uploads what was left and keeps a background run scheduled',
    () {
      queue.queue = UploadQueueSnapshot(batches: [testBatch(id: 'a')]);

      withCubit((async, cubit) {
        expect(api.uploadedIds, ['a']);
        expect(cubit.state.lastRun, const UploadRunSummary(uploaded: 1));
        expect(background.scheduleCount, 1);
      });
    },
  );

  test('with nothing to upload, no background run is scheduled', () {
    withCubit((async, cubit) => expect(background.scheduleCount, 0));
  });

  test(
    'reconnecting retries failed batches once the connection has been stable for 3 s',
    () {
      queue.queue = UploadQueueSnapshot(
        batches: [
          testBatch(
            id: 'f',
            status: UploadStatus.failed,
            retryCount: 1,
          ).copyWithNextAttempt(launch.add(const Duration(minutes: 10))),
        ],
      );

      withCubit(onlineAtLaunch: false, (async, cubit) {
        expect(cubit.state.isOnline, isFalse);

        goOnline(async, true);
        expect(cubit.state.isOnline, isTrue);
        async.elapse(const Duration(milliseconds: 2900));
        expect(api.uploadedIds, isEmpty, reason: 'not stable yet');

        async.elapse(const Duration(milliseconds: 200));
        expect(
          api.uploadedIds,
          ['f'],
          reason: 'retried without waiting out its 10-minute backoff',
        );
        expect(queue.queue.batches.single.status, UploadStatus.completed);
      });
    },
  );

  test('a connection that drops again within 3 s triggers nothing', () {
    queue.queue = UploadQueueSnapshot(
      batches: [testBatch(id: 'f', status: UploadStatus.failed, retryCount: 1)],
    );

    withCubit(onlineAtLaunch: false, (async, cubit) {
      final before = api.uploadedIds.length;
      goOnline(async, true);
      async.elapse(const Duration(seconds: 1));
      goOnline(async, false);
      async.elapse(const Duration(seconds: 10));

      expect(api.uploadedIds.length, before);
    });
  });

  test('a failed batch is retried by itself when its retry time comes', () {
    queue.queue = UploadQueueSnapshot(batches: [testBatch(id: 'a')]);
    api.script.add(FakeUploadApi.serverError);

    withCubit((async, cubit) {
      expect(api.uploadedIds, ['a']);
      expect(queue.queue.batches.single.status, UploadStatus.failed);

      async.elapse(const Duration(seconds: 29));
      expect(api.uploadedIds, ['a']);

      async.elapse(const Duration(seconds: 2));
      expect(api.uploadedIds, ['a', 'a']);
      expect(queue.queue.batches.single.status, UploadStatus.completed);
    });
  });

  test('timed retries pause while offline', () {
    queue.queue = UploadQueueSnapshot(batches: [testBatch(id: 'a')]);
    api.script.add(FakeUploadApi.serverError);

    withCubit((async, cubit) {
      goOnline(async, false);
      async.elapse(const Duration(minutes: 5));

      expect(api.uploadedIds, ['a'], reason: 'only the launch attempt');
    });
  });

  test(
    'if scheduling the background run fails, the upload still happens now',
    () {
      queue.queue = UploadQueueSnapshot(batches: [testBatch(id: 'a')]);
      background.throws = StateError('WorkManager unavailable');

      withCubit((async, cubit) {
        expect(api.uploadedIds, ['a']);
        expect(cubit.state.lastRunFailed, isFalse);
      });
    },
  );

  test('a storage error is retried after a pause, not in a tight loop', () {
    queue.queue = UploadQueueSnapshot(
      batches: [
        testBatch(
          id: 'f',
          status: UploadStatus.failed,
          retryCount: 1,
        ).copyWithNextAttempt(launch),
      ],
    );
    queue.claimThrows = const UploadQueueException('Disk full');

    withCubit((async, cubit) {
      expect(cubit.state.lastRunFailed, isTrue);
      expect(queue.claimFailures, 1);

      async.elapse(const Duration(seconds: 29));
      expect(queue.claimFailures, 1, reason: 'no immediate re-run');

      async.elapse(const Duration(seconds: 2));
      expect(queue.claimFailures, 2, reason: 'tried again after 30 s');

      queue.claimThrows = null;
      async.elapse(const Duration(seconds: 30));
      expect(api.uploadedIds, ['f']);
      expect(cubit.state.lastRunFailed, isFalse);
    });
  });

  test('closing stops every timer', () {
    queue.queue = UploadQueueSnapshot(batches: [testBatch(id: 'a')]);
    api.script.add(FakeUploadApi.serverError);

    fakeAsync((async) {
      DateTime now() => launch.add(async.elapsed);
      final cubit = SyncCubit(
        processQueue: ProcessUploadQueue(queue: queue, api: api, clock: now),
        queue: queue,
        backgroundSync: background,
        onlineChanges: connectivity.stream,
        isOnline: () async => true,
        clock: now,
      );
      unawaited(cubit.start());
      async.flushMicrotasks();
      unawaited(cubit.close());
      async.flushMicrotasks();

      async.elapse(const Duration(minutes: 5));
      expect(api.uploadedIds, ['a']);
    });
  });

  test('Retry now retries failed batches straight away', () {
    queue.queue = UploadQueueSnapshot(
      batches: [
        testBatch(
          id: 'f',
          status: UploadStatus.failed,
          retryCount: 1,
        ).copyWithNextAttempt(launch.add(const Duration(minutes: 10))),
      ],
    );

    withCubit((async, cubit) {
      expect(api.uploadedIds, isEmpty, reason: 'still in backoff at launch');
      unawaited(cubit.sync(retryFailedNow: true));
      async.flushMicrotasks();
      expect(api.uploadedIds, ['f']);
    });
  });

  test('exposes upload progress while a batch uploads, then clears it', () {
    queue.queue = UploadQueueSnapshot(batches: [testBatch(id: 'a')]);
    api.progressSteps = [0.65];

    withCubit(beforeStart: () => api.gate = Completer<void>(), (async, cubit) {
      final progress = cubit.state.progress['a']!;
      expect(progress.percent, 65);
      expect(progress.totalBytes, testBatch(id: 'a').totalBytes);

      api.gate!.complete();
      async.flushMicrotasks();

      expect(cubit.state.progress, isEmpty);
      expect(queue.queue.batches.single.status, UploadStatus.completed);
    });
  });
}
