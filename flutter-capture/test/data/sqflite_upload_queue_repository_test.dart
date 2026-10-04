import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tether_capture/data/datasources/photo_store.dart';
import 'package:tether_capture/data/datasources/upload_queue_database.dart';
import 'package:tether_capture/data/repositories/sqflite_upload_queue_repository.dart';
import 'package:tether_capture/domain/entities/captured_photo.dart';
import 'package:tether_capture/domain/entities/upload_batch.dart';
import 'package:tether_capture/domain/entities/upload_queue_snapshot.dart';
import 'package:tether_capture/domain/entities/upload_status.dart';
import 'package:tether_capture/domain/repositories/upload_queue_repository.dart';

void main() {
  sqfliteFfiInit();

  late Directory temp;
  late PhotoStore photos;
  late SqfliteUploadQueueRepository queue;
  late DateTime now;
  var ids = 0;
  var shots = 0;

  Future<SqfliteUploadQueueRepository> openQueue() async =>
      SqfliteUploadQueueRepository(
        database: await UploadQueueDatabase.open(
          p.join(temp.path, UploadQueueDatabase.fileName),
          factory: databaseFactoryFfi,
        ),
        photos: photos,
        clock: () => now,
        newId: () => 'id${++ids}',
      );

  /// A photo as the camera leaves it: a JPEG in the cache directory.
  Future<CapturedPhoto> takePhoto({int bytes = 1000}) async {
    final file = File(p.join(temp.path, 'cache', 'CAP${++shots}.jpg'));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(bytes, 7));
    now = now.add(const Duration(seconds: 1));
    return CapturedPhoto(path: file.path, capturedAt: now);
  }

  Future<UploadQueueSnapshot> current() => queue.watchQueue().first;

  Future<void> pumpUntil(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('upload_queue_test');
    photos = PhotoStore(Directory(p.join(temp.path, 'photos')));
    now = DateTime(2026, 10, 4, 12);
    queue = await openQueue();
  });

  tearDown(() async {
    await queue.close();
    await temp.delete(recursive: true);
  });

  test('the first photo starts a draft batch and leaves the cache', () async {
    final photo = await takePhoto(bytes: 2048);

    final item = await queue.addToDraft(photo);

    expect(File(photo.path).existsSync(), isFalse, reason: 'moved, not copied');
    expect(File(item.filePath).existsSync(), isTrue);
    expect(p.isWithin(photos.root.path, item.filePath), isTrue);
    expect(item.sizeBytes, 2048);
    expect(item.status, UploadStatus.pending);
    final queued = await current();
    expect(queued.draft!.items, [item]);
    expect(queued.batches, isEmpty);
  });

  test('later photos join the same draft, in capture order', () async {
    final first = await queue.addToDraft(await takePhoto());
    final second = await queue.addToDraft(await takePhoto());
    final third = await queue.addToDraft(await takePhoto());

    final draft = (await current()).draft!;
    expect(draft.items, [first, second, third]);
    expect(draft.status, UploadStatus.draft);
  });

  test(
    'submitting queues the draft; the next photo starts a new batch',
    () async {
      await queue.addToDraft(await takePhoto());
      await queue.addToDraft(await takePhoto());
      final firstBatch = await queue.submitDraft();
      await queue.addToDraft(await takePhoto());
      final secondBatch = await queue.submitDraft();

      final queued = await current();
      expect(queued.draft, isNull);
      expect(queued.batches.map((b) => b.id), [
        secondBatch!.id,
        firstBatch!.id,
      ]);
      expect(queued.batches.map((b) => b.photoCount), [1, 2]);
      expect(
        queued.batches.every((b) => b.status == UploadStatus.pending),
        isTrue,
      );
      expect(firstBatch.submittedAt, isNotNull);
      expect(firstBatch.retryCount, 0);
    },
  );

  test('submitting without a draft does nothing', () async {
    expect(await queue.submitDraft(), isNull);
    expect((await current()).batches, isEmpty);
  });

  test('the queue and its photos survive an app restart', () async {
    await queue.addToDraft(await takePhoto());
    await queue.addToDraft(await takePhoto());
    final submitted = await queue.submitDraft();
    final draftPhoto = await queue.addToDraft(await takePhoto());

    await queue.close();
    queue = await openQueue();

    final queued = await current();
    expect(queued.batches.single, submitted);
    expect(queued.draft!.items.single, draftPhoto);
    for (final item in [...submitted!.items, draftPhoto]) {
      expect(File(item.filePath).existsSync(), isTrue);
    }
  });

  test('photo paths are stored relative to the photo folder', () async {
    await queue.addToDraft(await takePhoto());
    await queue.close();
    final db = await UploadQueueDatabase.open(
      p.join(temp.path, UploadQueueDatabase.fileName),
      factory: databaseFactoryFfi,
    );

    final stored =
        (await db.query(UploadQueueDatabase.items)).single['file_path']!
            as String;

    expect(p.isRelative(stored), isTrue);
    queue = await openQueue();
    await db.close();
  });

  test(
    'a photo that cannot be saved is reported and nothing is queued',
    () async {
      final missing = CapturedPhoto(
        path: p.join(temp.path, 'cache', 'gone.jpg'),
        capturedAt: now,
      );

      await expectLater(
        queue.addToDraft(missing),
        throwsA(isA<UploadQueueException>()),
      );

      expect((await current()).draft?.photoCount ?? 0, 0);
    },
  );

  test('an open watcher receives the queue again after every change', () async {
    String describe(UploadQueueSnapshot s) =>
        'draft:${s.draft?.photoCount ?? '-'} batches:${s.batches.length}';
    final seen = <String>[];
    final subscription = queue.watchQueue().map(describe).listen(seen.add);
    addTearDown(subscription.cancel);
    // Writes close together may be reported as one update (the watcher always
    // gets the latest state), so wait for each before making the next.
    Future<void> expectLatest(String expected) async {
      for (var i = 0; i < 200 && (seen.isEmpty || seen.last != expected); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(seen.last, expected);
    }

    await expectLatest('draft:- batches:0');
    await queue.addToDraft(await takePhoto());
    await expectLatest('draft:1 batches:0');
    await queue.addToDraft(await takePhoto());
    await expectLatest('draft:2 batches:0');
    await queue.submitDraft();
    await expectLatest('draft:- batches:1');
  });

  group('upload engine operations', () {
    Future<String> queueBatch({int photos = 2}) async {
      for (var i = 0; i < photos; i++) {
        await queue.addToDraft(await takePhoto());
      }
      return (await queue.submitDraft())!.id;
    }

    Future<UploadBatch> batch(String id) async =>
        (await current()).batches.firstWhere((b) => b.id == id);

    test(
      'claiming marks the oldest due batch and its photos as uploading',
      () async {
        final first = await queueBatch();
        await queueBatch();

        final claimed = await queue.claimNextDueBatch(now: now);

        expect(claimed!.id, first);
        expect(claimed.status, UploadStatus.uploading);
        expect(
          claimed.items.every((i) => i.status == UploadStatus.uploading),
          isTrue,
        );
      },
    );

    test('a claimed batch cannot be claimed again', () async {
      final id = await queueBatch();

      expect((await queue.claimNextDueBatch(now: now))!.id, id);
      expect(await queue.claimNextDueBatch(now: now), isNull);
    });

    test('drafts are never claimed', () async {
      await queue.addToDraft(await takePhoto());

      expect(await queue.claimNextDueBatch(now: now), isNull);
    });

    test('success completes the batch, then deletes its photo files', () async {
      final id = await queueBatch();
      final claimed = await queue.claimNextDueBatch(now: now);

      await queue.markCompleted(id);

      final done = await batch(id);
      expect(done.status, UploadStatus.completed);
      expect(
        done.items.every((i) => i.status == UploadStatus.completed),
        isTrue,
      );
      for (final item in claimed!.items) {
        expect(File(item.filePath).existsSync(), isFalse);
      }
    });

    test(
      'failure keeps the photos and the record, and makes a retry possible',
      () async {
        final id = await queueBatch();
        final claimed = await queue.claimNextDueBatch(now: now);
        final retryAt = now.add(const Duration(seconds: 30));

        await queue.markFailed(
          id,
          error: 'No internet connection.',
          nextAttemptAt: retryAt,
        );

        final failed = await batch(id);
        expect(failed.status, UploadStatus.failed);
        expect(failed.retryCount, 1);
        expect(failed.items.every((i) => i.retryCount == 1), isTrue);
        expect(failed.lastError, 'No internet connection.');
        expect(failed.nextAttemptAt, retryAt);
        for (final item in claimed!.items) {
          expect(
            File(item.filePath).existsSync(),
            isTrue,
            reason: 'image remains',
          );
        }
        // Retry possible: not before its time, then yes.
        expect(await queue.claimNextDueBatch(now: now), isNull);
        expect((await queue.claimNextDueBatch(now: retryAt))!.id, id);
      },
    );

    test(
      'a failed batch survives a restart and can still be retried',
      () async {
        final id = await queueBatch();
        await queue.claimNextDueBatch(now: now);
        await queue.markFailed(id, error: 'Timed out.', nextAttemptAt: now);

        await queue.close();
        queue = await openQueue();

        expect((await batch(id)).status, UploadStatus.failed);
        expect((await queue.claimNextDueBatch(now: now))!.id, id);
      },
    );

    test('Retry now makes failed batches due immediately', () async {
      final id = await queueBatch();
      await queue.claimNextDueBatch(now: now);
      await queue.markFailed(
        id,
        error: 'x',
        nextAttemptAt: now.add(const Duration(minutes: 15)),
      );

      expect(await queue.makeFailedDueNow(now: now), 1);

      expect((await queue.claimNextDueBatch(now: now))!.id, id);
    });

    test('an upload abandoned past the lease goes back to pending', () async {
      final id = await queueBatch();
      await queue.claimNextDueBatch(now: now);

      expect(
        await queue.recoverInterruptedUploads(olderThan: now),
        0,
        reason: 'still within lease',
      );
      final recovered = await queue.recoverInterruptedUploads(
        olderThan: now.add(const Duration(minutes: 6)),
      );

      expect(recovered, 1);
      final back = await batch(id);
      expect(back.status, UploadStatus.pending);
      expect(back.items.every((i) => i.status == UploadStatus.pending), isTrue);
      expect(back.lastError, contains('interrupted'));
    });

    test('a late failure never undoes a completed upload', () async {
      final id = await queueBatch();
      // Run A claims the batch, then stalls past the lease.
      await queue.claimNextDueBatch(now: now);
      final later = now.add(const Duration(minutes: 6));
      await queue.recoverInterruptedUploads(olderThan: later);
      // Run B takes it over and uploads it.
      await queue.claimNextDueBatch(now: later);
      await queue.markCompleted(id);

      // Run A finally gives up.
      await queue.markFailed(
        id,
        error: 'Timed out.',
        nextAttemptAt: later.add(const Duration(seconds: 30)),
      );

      final done = await batch(id);
      expect(done.status, UploadStatus.completed);
      expect(done.retryCount, 0);
      expect(done.lastError, isNull);
      expect(await queue.hasUnfinishedUploads(), isFalse);
    });

    test('reports when the earliest failed batch may be retried', () async {
      final a = await queueBatch();
      final b = await queueBatch();
      await queue.claimNextDueBatch(now: now);
      await queue.claimNextDueBatch(now: now);
      await queue.markFailed(
        a,
        error: 'x',
        nextAttemptAt: now.add(const Duration(minutes: 4)),
      );
      await queue.markFailed(
        b,
        error: 'x',
        nextAttemptAt: now.add(const Duration(minutes: 1)),
      );

      expect(await queue.nextRetryAt(), now.add(const Duration(minutes: 1)));
    });

    test('knows whether any submitted batch is still unfinished', () async {
      expect(await queue.hasUnfinishedUploads(), isFalse);
      await queue.addToDraft(await takePhoto());
      expect(
        await queue.hasUnfinishedUploads(),
        isFalse,
        reason: 'drafts do not count',
      );

      final id = (await queue.submitDraft())!.id;
      expect(await queue.hasUnfinishedUploads(), isTrue);

      await queue.claimNextDueBatch(now: now);
      await queue.markCompleted(id);
      expect(await queue.hasUnfinishedUploads(), isFalse);
    });

    test('two workers claiming at once never get the same batch', () async {
      // Like the app and the background worker: two independent repositories
      // (no shared in-memory state or write queue) on the one connection
      // that sqflite gives both isolates on Android.
      final ids = {for (var i = 0; i < 6; i++) await queueBatch(photos: 1)};
      final other = SqfliteUploadQueueRepository(
        database: await UploadQueueDatabase.open(
          p.join(temp.path, UploadQueueDatabase.fileName),
          factory: databaseFactoryFfi,
        ),
        photos: photos,
        clock: () => now,
      );

      Future<List<String>> drain(SqfliteUploadQueueRepository worker) async {
        final claimed = <String>[];
        while (true) {
          final batch = await worker.claimNextDueBatch(now: now);
          if (batch == null) return claimed;
          claimed.add(batch.id);
        }
      }

      final results = await Future.wait([drain(queue), drain(other)]);

      final all = [...results[0], ...results[1]];
      expect(all, hasLength(6), reason: 'every batch claimed exactly once');
      expect(all.toSet(), ids);
    });
  });

  test(
    'a version 1 database is upgraded in place, keeping its queue',
    () async {
      await queue.close();
      final path = p.join(temp.path, 'v1.db');
      final v1 = await UploadQueueDatabase.open(
        path,
        factory: databaseFactoryFfi,
        targetVersion: 1,
      );
      await v1.insert(UploadQueueDatabase.batches, {
        'id': 'old',
        'created_at': 0,
        'status': 'pending',
        'updated_at': 0,
      });
      await v1.close();

      final v2 = await UploadQueueDatabase.open(
        path,
        factory: databaseFactoryFfi,
      );
      final rows = await v2.query(UploadQueueDatabase.batches);
      expect(await v2.getVersion(), UploadQueueDatabase.version);
      expect(rows.single['id'], 'old');
      expect(rows.single.containsKey('next_attempt_at'), isTrue);
      await v2.close();
      queue = await openQueue();
    },
  );

  test('photo files nothing points to are removed, queued ones kept', () async {
    // A completed batch whose files survived (killed before deleting them).
    await queue.addToDraft(await takePhoto());
    final uploaded = await queue.submitDraft();
    await queue.claimNextDueBatch(now: now);
    await queue.markCompleted(uploaded!.id);
    final survivor = File(photos.absolutePath(p.join(uploaded.id, 'a.jpg')));
    await survivor.create(recursive: true);
    // A pending batch and the draft, each with a stray file (killed between
    // moving a photo in and recording it), plus a folder of no known batch.
    await queue.addToDraft(await takePhoto());
    final pending = await queue.submitDraft();
    final draftPhoto = await queue.addToDraft(await takePhoto());
    final strays = [
      File(photos.absolutePath(p.join(pending!.id, 'stray.jpg'))),
      File(photos.absolutePath(p.join(draftPhoto.batchId, 'stray.jpg'))),
      File(photos.absolutePath(p.join('unknown', 'x.jpg'))),
    ];
    for (final stray in strays) {
      await stray.create(recursive: true);
    }

    expect(await queue.deleteOrphanedPhotos(), 4);

    expect(survivor.parent.existsSync(), isFalse);
    expect(strays.where((f) => f.existsSync()), isEmpty);
    expect(Directory(photos.absolutePath('unknown')).existsSync(), isFalse);
    expect(File(pending.items.single.filePath).existsSync(), isTrue);
    expect(File(draftPhoto.filePath).existsSync(), isTrue);
    expect(await queue.deleteOrphanedPhotos(), 0, reason: 'nothing left');
  });

  test('cleaning up with no photo folder yet does nothing', () async {
    expect(await queue.deleteOrphanedPhotos(), 0);
  });

  group('changes made by another isolate', () {
    // The background worker has its own repository on the same database.
    Future<SqfliteUploadQueueRepository> openWorkerQueue({
      void Function()? onWrite,
    }) async => SqfliteUploadQueueRepository(
      database: await UploadQueueDatabase.open(
        p.join(temp.path, UploadQueueDatabase.fileName),
        factory: databaseFactoryFfi,
      ),
      photos: photos,
      clock: () => now,
      onWrite: onWrite,
    );

    test('reach open watchers once announced, not before', () async {
      await queue.addToDraft(await takePhoto());
      final id = (await queue.submitDraft())!.id;
      final seen = <UploadStatus>[];
      final subscription = queue.watchQueue().listen(
        (s) => seen.add(s.batches.single.status),
      );
      addTearDown(subscription.cancel);
      await pumpUntil(() => seen.isNotEmpty);

      final worker = await openWorkerQueue();
      await worker.claimNextDueBatch(now: now);
      await worker.markCompleted(id);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        seen.last,
        UploadStatus.pending,
        reason: 'the bug: no notice, stale screen',
      );

      queue.notifyExternalChange();
      await pumpUntil(() => seen.last == UploadStatus.completed);
      expect(seen.last, UploadStatus.completed);
    });

    test('every write is reported, so the worker can announce it', () async {
      var writes = 0;
      final worker = await openWorkerQueue(onWrite: () => writes++);

      await worker.addToDraft(await takePhoto());
      final id = (await worker.submitDraft())!.id;
      await worker.claimNextDueBatch(now: now);
      await worker.markFailed(id, error: 'x', nextAttemptAt: now);
      await worker.makeFailedDueNow(now: now);
      await worker.claimNextDueBatch(now: now);
      await worker.markCompleted(id);

      expect(writes, 7);
    });
  });

  group('schema', () {
    late Database db;

    setUp(() async {
      await queue.close();
      db = await UploadQueueDatabase.open(
        p.join(temp.path, UploadQueueDatabase.fileName),
        factory: databaseFactoryFfi,
      );
    });

    tearDown(() async {
      await db.close();
      queue = await openQueue();
    });

    Map<String, Object?> batchRow(String id, String status) => {
      'id': id,
      'created_at': 0,
      'status': status,
      'updated_at': 0,
    };

    test('allows only one draft batch', () async {
      await db.insert(UploadQueueDatabase.batches, batchRow('a', 'draft'));

      await expectLater(
        db.insert(UploadQueueDatabase.batches, batchRow('b', 'draft')),
        throwsA(isA<DatabaseException>()),
      );
      await db.insert(UploadQueueDatabase.batches, batchRow('c', 'pending'));
    });

    test('rejects unknown statuses', () async {
      await expectLater(
        db.insert(UploadQueueDatabase.batches, batchRow('a', 'lost')),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('rejects a photo whose batch does not exist', () async {
      await expectLater(
        db.insert(UploadQueueDatabase.items, {
          'id': 'i',
          'batch_id': 'nope',
          'file_path': 'x.jpg',
          'status': 'pending',
          'size_bytes': 1,
          'created_at': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
