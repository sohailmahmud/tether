import '../entities/captured_photo.dart';
import '../entities/upload_batch.dart';
import '../entities/upload_item.dart';
import '../entities/upload_queue_snapshot.dart';

/// The persistent local queue of photos waiting to be uploaded.
///
/// Survives app restarts. A photo's file and record are only removed after
/// the server confirms the upload.
abstract interface class UploadQueueRepository {
  /// Emits the current queue, then again after every change.
  Stream<UploadQueueSnapshot> watchQueue();

  /// Moves [photo] into permanent app storage and adds it to the draft batch,
  /// starting a new draft if there is none.
  ///
  /// Throws [UploadQueueException].
  Future<UploadItem> addToDraft(CapturedPhoto photo);

  /// Sends the draft batch for upload (draft → pending). The next photo
  /// starts a new batch. Returns null if there is no draft.
  ///
  /// Throws [UploadQueueException].
  Future<UploadBatch?> submitDraft();
}

/// The queue could not be read or written (storage full, file missing…).
class UploadQueueException implements Exception {
  const UploadQueueException(this.message, [this.cause]);

  final String message;

  /// The underlying error, for logs only.
  final Object? cause;

  @override
  String toString() => 'UploadQueueException($message, $cause)';
}
