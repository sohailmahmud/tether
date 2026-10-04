import 'dart:async';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../core/id_generator.dart';
import '../../domain/entities/captured_photo.dart';
import '../../domain/entities/upload_batch.dart';
import '../../domain/entities/upload_item.dart';
import '../../domain/entities/upload_queue_snapshot.dart';
import '../../domain/entities/upload_status.dart';
import '../../domain/repositories/upload_queue_repository.dart';
import '../datasources/photo_store.dart';
import '../datasources/upload_queue_database.dart';

/// [UploadQueueRepository] stored in SQLite, with photo files in [PhotoStore].
class SqfliteUploadQueueRepository implements UploadQueueRepository {
  SqfliteUploadQueueRepository({
    required Database database,
    required this._photos,
    this._clock = DateTime.now,
    this._newId = newId,
    this._onWrite,
  }) : _db = database;

  static const _batches = UploadQueueDatabase.batches;
  static const _items = UploadQueueDatabase.items;

  final Database _db;
  final PhotoStore _photos;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// Called after every write. The background worker uses it to tell the
  /// app's isolate, which has its own repository and watchers, to reload.
  final void Function()? _onWrite;

  /// Fires after every write, so open queue watchers reload.
  final _changes = StreamController<void>.broadcast();

  /// Writes from this process run one at a time, in order. (Transactions
  /// still guard each write against other isolates.)
  Future<void> _writes = Future<void>.value();

  @override
  Stream<UploadQueueSnapshot> watchQueue() => Stream.multi((controller) {
    // Reloads run one after another, so snapshots arrive in the order the
    // database changed and an older one never replaces a newer one.
    var reloading = Future<void>.value();
    void reload() {
      reloading = reloading.then((_) async {
        try {
          final snapshot = await _snapshot();
          if (!controller.isClosed) controller.add(snapshot);
        } on DatabaseException catch (e, stack) {
          if (!controller.isClosed) {
            controller.addError(
              UploadQueueException('The upload queue could not be read', e),
              stack,
            );
          }
        }
      });
    }

    final subscription = _changes.stream.listen((_) => reload());
    reload();
    controller.onCancel = subscription.cancel;
  });

  @override
  Future<UploadItem> addToDraft(CapturedPhoto photo) => _write(() async {
    final String batchId;
    try {
      batchId = await _db.transaction(_draftBatchId);
    } on DatabaseException catch (e) {
      throw UploadQueueException('The photo could not be added', e);
    }

    final itemId = _newId();
    final String relativePath;
    final int sizeBytes;
    try {
      relativePath = await _photos.keep(
        photo.path,
        batchId: batchId,
        itemId: itemId,
      );
      sizeBytes = await File(_photos.absolutePath(relativePath)).length();
    } on FileSystemException catch (e) {
      throw UploadQueueException('The photo could not be saved', e);
    }

    final item = UploadItem(
      id: itemId,
      batchId: batchId,
      filePath: _photos.absolutePath(relativePath),
      status: UploadStatus.pending,
      retryCount: 0,
      createdAt: photo.capturedAt,
      sizeBytes: sizeBytes,
    );
    try {
      await _db.insert(_items, {
        'id': item.id,
        'batch_id': batchId,
        'file_path': relativePath,
        'status': item.status.name,
        'retry_count': 0,
        'size_bytes': sizeBytes,
        'created_at': item.createdAt.millisecondsSinceEpoch,
      });
    } on DatabaseException catch (e) {
      // Don't leave a file that no record points to.
      await _photos.delete(relativePath);
      throw UploadQueueException('The photo could not be added', e);
    }
    _notifyWrite();
    return item;
  });

  @override
  Future<UploadBatch?> submitDraft() => _write(() async {
    final String? batchId;
    try {
      batchId = await _db.transaction((txn) async {
        final rows = await txn.rawQuery(
          'SELECT b.id, COUNT(i.id) AS photos FROM $_batches b '
          'LEFT JOIN $_items i ON i.batch_id = b.id '
          'WHERE b.status = ? GROUP BY b.id',
          [UploadStatus.draft.name],
        );
        if (rows.isEmpty || (rows.single['photos']! as int) == 0) return null;
        final id = rows.single['id']! as String;
        final now = _clock().millisecondsSinceEpoch;
        await txn.update(
          _batches,
          {
            'status': UploadStatus.pending.name,
            'submitted_at': now,
            'updated_at': now,
          },
          where: 'id = ? AND status = ?',
          whereArgs: [id, UploadStatus.draft.name],
        );
        return id;
      });
    } on DatabaseException catch (e) {
      throw UploadQueueException('The batch could not be submitted', e);
    }
    if (batchId == null) return null;
    _notifyWrite();
    final snapshot = await _snapshot();
    return snapshot.batches.firstWhere((batch) => batch.id == batchId);
  });

  @override
  Future<UploadBatch?> claimNextDueBatch({
    required DateTime now,
  }) => _write(() async {
    final String? batchId;
    try {
      // Select and update in one transaction: on Android the plugin queues
      // other isolates' calls until it commits, so the background worker
      // can't read the same batch in between. EXCLUSIVE extends that to any
      // other connection to the file.
      batchId = await _db.transaction((txn) async {
        final rows = await txn.query(
          _batches,
          columns: ['id', 'status'],
          where:
              'status = ? OR (status = ? AND (next_attempt_at IS NULL OR next_attempt_at <= ?))',
          whereArgs: [
            UploadStatus.pending.name,
            UploadStatus.failed.name,
            now.millisecondsSinceEpoch,
          ],
          orderBy: 'submitted_at, created_at',
          limit: 1,
        );
        if (rows.isEmpty) return null;
        final id = rows.single['id']! as String;
        // Conditional on the status just read: a second guard against a
        // double claim, independent of the transaction mode.
        final claimed = await txn.update(
          _batches,
          {
            'status': UploadStatus.uploading.name,
            'updated_at': now.millisecondsSinceEpoch,
          },
          where: 'id = ? AND status = ?',
          whereArgs: [id, rows.single['status']],
        );
        if (claimed != 1) return null;
        await txn.update(
          _items,
          {'status': UploadStatus.uploading.name},
          where: 'batch_id = ?',
          whereArgs: [id],
        );
        return id;
      }, exclusive: true);
    } on DatabaseException catch (e) {
      throw UploadQueueException('The next upload could not be started', e);
    }
    if (batchId == null) return null;
    _notifyWrite();
    return _loadBatch(batchId);
  });

  @override
  Future<int> makeFailedDueNow({required DateTime now}) => _write(() async {
    final count = await _db.update(
      _batches,
      {'next_attempt_at': now.millisecondsSinceEpoch},
      where: 'status = ?',
      whereArgs: [UploadStatus.failed.name],
    );
    if (count > 0) _notifyWrite();
    return count;
  });

  @override
  Future<void> markCompleted(String batchId) => _write(() async {
    final now = _clock().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      await txn.update(
        _batches,
        {
          'status': UploadStatus.completed.name,
          'last_error': null,
          'next_attempt_at': null,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [batchId],
      );
      await txn.update(
        _items,
        {'status': UploadStatus.completed.name},
        where: 'batch_id = ?',
        whereArgs: [batchId],
      );
    });
    // Files go only after the completed status is committed. If the app dies
    // in between, the files remain and nothing is lost.
    await _photos.deleteBatch(batchId);
    _notifyWrite();
  });

  @override
  Future<void> markFailed(
    String batchId, {
    required String error,
    required DateTime nextAttemptAt,
  }) => _write(() async {
    final now = _clock().millisecondsSinceEpoch;
    final updated = await _db.transaction((txn) async {
      // Only an upload still in progress can fail. If this attempt outlived
      // its lease and another run has since completed the batch (and deleted
      // its files), the late failure must not bring it back.
      final batches = await txn.rawUpdate(
        'UPDATE $_batches SET status = ?, retry_count = retry_count + 1, '
        'last_error = ?, next_attempt_at = ?, updated_at = ? '
        'WHERE id = ? AND status = ?',
        [
          UploadStatus.failed.name,
          error,
          nextAttemptAt.millisecondsSinceEpoch,
          now,
          batchId,
          UploadStatus.uploading.name,
        ],
      );
      if (batches == 0) return false;
      await txn.rawUpdate(
        'UPDATE $_items SET status = ?, retry_count = retry_count + 1 WHERE batch_id = ?',
        [UploadStatus.failed.name, batchId],
      );
      return true;
    });
    if (updated) _notifyWrite();
  });

  @override
  Future<int> recoverInterruptedUploads({required DateTime olderThan}) =>
      _write(() async {
        final recovered = await _db.transaction((txn) async {
          final rows = await txn.query(
            _batches,
            columns: ['id'],
            where: 'status = ? AND updated_at < ?',
            whereArgs: [
              UploadStatus.uploading.name,
              olderThan.millisecondsSinceEpoch,
            ],
          );
          for (final row in rows) {
            final id = row['id']! as String;
            await txn.update(
              _batches,
              {
                'status': UploadStatus.pending.name,
                'last_error': 'The previous upload attempt was interrupted.',
                'updated_at': _clock().millisecondsSinceEpoch,
              },
              where: 'id = ? AND status = ?',
              whereArgs: [id, UploadStatus.uploading.name],
            );
            await txn.update(
              _items,
              {'status': UploadStatus.pending.name},
              where: 'batch_id = ?',
              whereArgs: [id],
            );
          }
          return rows.length;
        });
        if (recovered > 0) _notifyWrite();
        return recovered;
      });

  @override
  Future<DateTime?> nextRetryAt() async {
    final rows = await _db.rawQuery(
      'SELECT MIN(next_attempt_at) AS next FROM $_batches WHERE status = ?',
      [UploadStatus.failed.name],
    );
    final next = rows.single['next'] as int?;
    return next == null ? null : DateTime.fromMillisecondsSinceEpoch(next);
  }

  @override
  Future<bool> hasUnfinishedUploads() async {
    final rows = await _db.query(
      _batches,
      columns: ['id'],
      where: 'status IN (?, ?, ?)',
      whereArgs: [
        UploadStatus.pending.name,
        UploadStatus.uploading.name,
        UploadStatus.failed.name,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Deletes photo files that no queued photo points to, and returns how many
  /// folders and files were removed. They are left behind only if the app is
  /// killed at the wrong moment: after an upload is completed but before its
  /// files are deleted, or after a photo is moved into the queue but before
  /// it is recorded.
  ///
  /// Only for the app's isolate, the one that adds photos: its own additions
  /// are serialized with this, while one in another isolate could be caught
  /// half-done.
  Future<int> deleteOrphanedPhotos() => _write(() async {
    final rows = await _db.rawQuery(
      'SELECT b.id, b.status, i.file_path FROM $_batches b '
      'LEFT JOIN $_items i ON i.batch_id = b.id',
    );
    final liveBatches = <String>{};
    final keptPhotos = <String>{};
    for (final row in rows) {
      if (row['status'] == UploadStatus.completed.name) continue;
      liveBatches.add(row['id']! as String);
      final path = row['file_path'] as String?;
      if (path != null) keptPhotos.add(path);
    }

    var removed = 0;
    for (final batchId in await _photos.batchIds()) {
      if (!liveBatches.contains(batchId)) {
        await _photos.deleteBatch(batchId);
        removed++;
        continue;
      }
      for (final photo in await _photos.photosOf(batchId)) {
        if (!keptPhotos.contains(photo)) {
          await _photos.delete(photo);
          removed++;
        }
      }
    }
    return removed;
  });

  /// Another isolate (the background worker) changed the queue: reload every
  /// open watcher from the database.
  void notifyExternalChange() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void _notifyWrite() {
    _changes.add(null);
    _onWrite?.call();
  }

  /// Releases the database. The app never needs this; tests do.
  Future<void> close() async {
    await _changes.close();
    await _db.close();
  }

  /// The open draft's id, creating the draft if there is none.
  Future<String> _draftBatchId(Transaction txn) async {
    final rows = await txn.query(
      _batches,
      columns: ['id'],
      where: 'status = ?',
      whereArgs: [UploadStatus.draft.name],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.single['id']! as String;
    final id = _newId();
    final now = _clock().millisecondsSinceEpoch;
    await txn.insert(_batches, {
      'id': id,
      'created_at': now,
      'status': UploadStatus.draft.name,
      'retry_count': 0,
      'updated_at': now,
    });
    return id;
  }

  Future<UploadBatch> _loadBatch(String id) => _db.transaction((txn) async {
    final batchRow = (await txn.query(
      _batches,
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    final itemRows = await txn.query(
      _items,
      where: 'batch_id = ?',
      whereArgs: [id],
      orderBy: 'created_at, id',
    );
    return _batchFromRow(batchRow, itemRows.map(_itemFromRow).toList());
  });

  /// Reads batches and items in one transaction, so they are consistent.
  Future<UploadQueueSnapshot> _snapshot() => _db.transaction((txn) async {
    final batchRows = await txn.query(
      _batches,
      orderBy: 'COALESCE(submitted_at, created_at) DESC',
    );
    final itemRows = await txn.query(_items, orderBy: 'created_at, id');

    final itemsByBatch = <String, List<UploadItem>>{};
    for (final row in itemRows) {
      final item = _itemFromRow(row);
      (itemsByBatch[item.batchId] ??= []).add(item);
    }
    UploadBatch? draft;
    final submitted = <UploadBatch>[];
    for (final row in batchRows) {
      final batch = _batchFromRow(row, itemsByBatch[row['id']] ?? const []);
      if (batch.status == UploadStatus.draft) {
        draft = batch;
      } else {
        submitted.add(batch);
      }
    }
    return UploadQueueSnapshot(draft: draft, batches: submitted);
  });

  UploadItem _itemFromRow(Map<String, Object?> row) => UploadItem(
    id: row['id']! as String,
    batchId: row['batch_id']! as String,
    filePath: _photos.absolutePath(row['file_path']! as String),
    status: UploadStatus.values.byName(row['status']! as String),
    retryCount: row['retry_count']! as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    sizeBytes: row['size_bytes']! as int,
  );

  UploadBatch _batchFromRow(Map<String, Object?> row, List<UploadItem> items) {
    final submittedAt = row['submitted_at'] as int?;
    final nextAttemptAt = row['next_attempt_at'] as int?;
    return UploadBatch(
      id: row['id']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      status: UploadStatus.values.byName(row['status']! as String),
      retryCount: row['retry_count']! as int,
      lastError: row['last_error'] as String?,
      submittedAt: submittedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(submittedAt),
      nextAttemptAt: nextAttemptAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(nextAttemptAt),
      items: items,
    );
  }

  Future<T> _write<T>(Future<T> Function() write) {
    final result = _writes.then((_) => write());
    // A failed write must not block the ones queued after it.
    _writes = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
