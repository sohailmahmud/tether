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
  }) : _db = database;

  static const _batches = UploadQueueDatabase.batches;
  static const _items = UploadQueueDatabase.items;

  final Database _db;
  final PhotoStore _photos;
  final DateTime Function() _clock;
  final String Function() _newId;

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
    _changes.add(null);
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
    _changes.add(null);
    final snapshot = await _snapshot();
    return snapshot.batches.firstWhere((batch) => batch.id == batchId);
  });

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
    return UploadBatch(
      id: row['id']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      status: UploadStatus.values.byName(row['status']! as String),
      retryCount: row['retry_count']! as int,
      lastError: row['last_error'] as String?,
      submittedAt: submittedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(submittedAt),
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
