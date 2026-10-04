import 'dart:async';

import 'package:tether_capture/domain/entities/captured_photo.dart';
import 'package:tether_capture/domain/entities/upload_batch.dart';
import 'package:tether_capture/domain/entities/upload_item.dart';
import 'package:tether_capture/domain/entities/upload_queue_snapshot.dart';
import 'package:tether_capture/domain/entities/upload_status.dart';
import 'package:tether_capture/domain/repositories/upload_queue_repository.dart';

/// A batch for screen tests.
UploadBatch testBatch({
  String id = 'batch',
  UploadStatus status = UploadStatus.pending,
  int photos = 3,
  int retryCount = 0,
  String? lastError,
}) => UploadBatch(
  id: id,
  createdAt: DateTime(2026, 10, 4, 20, 10),
  submittedAt: DateTime(2026, 10, 4, 20, 10),
  status: status,
  retryCount: retryCount,
  lastError: lastError,
  items: [
    for (var i = 0; i < photos; i++)
      UploadItem(
        id: '$id-$i',
        batchId: id,
        filePath: '/photos/$id/$i.jpg',
        status: UploadStatus.pending,
        retryCount: 0,
        createdAt: DateTime(2026, 10, 4, 20, i),
        sizeBytes: 512 * 1024,
      ),
  ],
);

/// In-memory [UploadQueueRepository] that can be told to fail.
class FakeUploadQueueRepository implements UploadQueueRepository {
  FakeUploadQueueRepository([this._queue = const UploadQueueSnapshot()]);

  UploadQueueSnapshot _queue;
  final _changes = StreamController<UploadQueueSnapshot>.broadcast();
  var _ids = 0;

  bool addFails = false;
  bool submitFails = false;

  /// When set, watchQueue() reports this error instead of the queue.
  Object? readError;

  UploadQueueSnapshot get queue => _queue;

  set queue(UploadQueueSnapshot value) {
    _queue = value;
    _changes.add(value);
  }

  @override
  Stream<UploadQueueSnapshot> watchQueue() => Stream.multi((controller) {
    final error = readError;
    if (error != null) {
      controller.addError(error);
      return;
    }
    controller.add(_queue);
    final subscription = _changes.stream.listen(controller.add);
    controller.onCancel = subscription.cancel;
  });

  @override
  Future<UploadItem> addToDraft(CapturedPhoto photo) async {
    if (addFails) throw const UploadQueueException('disk full');
    final draft = _queue.draft;
    final batchId = draft?.id ?? 'batch${++_ids}';
    final item = UploadItem(
      id: 'item${++_ids}',
      batchId: batchId,
      filePath: photo.path,
      status: UploadStatus.pending,
      retryCount: 0,
      createdAt: photo.capturedAt,
      sizeBytes: 1000,
    );
    queue = UploadQueueSnapshot(
      draft: UploadBatch(
        id: batchId,
        createdAt: draft?.createdAt ?? photo.capturedAt,
        status: UploadStatus.draft,
        retryCount: 0,
        items: [...?draft?.items, item],
      ),
      batches: _queue.batches,
    );
    return item;
  }

  @override
  Future<UploadBatch?> submitDraft() async {
    if (submitFails) throw const UploadQueueException('disk full');
    final draft = _queue.draft;
    if (draft == null || draft.items.isEmpty) return null;
    final submitted = UploadBatch(
      id: draft.id,
      createdAt: draft.createdAt,
      submittedAt: draft.createdAt,
      status: UploadStatus.pending,
      retryCount: 0,
      items: draft.items,
    );
    queue = UploadQueueSnapshot(batches: [submitted, ..._queue.batches]);
    return submitted;
  }
}
