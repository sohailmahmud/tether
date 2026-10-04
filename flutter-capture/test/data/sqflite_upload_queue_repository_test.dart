import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tether_capture/data/datasources/photo_store.dart';
import 'package:tether_capture/data/datasources/upload_queue_database.dart';
import 'package:tether_capture/data/repositories/sqflite_upload_queue_repository.dart';
import 'package:tether_capture/domain/entities/captured_photo.dart';
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
