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

  /// Atomically claims the oldest batch that is due for upload, marking it
  /// uploading, so no other worker (in this or another isolate) can claim it.
  ///
  /// Due means pending, or failed with its retry time reached ([now]).
  /// Returns null when nothing is due.
  Future<UploadBatch?> claimNextDueBatch({required DateTime now});

  /// Makes every failed batch due at [now], for a manual "Retry now".
  /// Returns how many were waiting.
  Future<int> makeFailedDueNow({required DateTime now});

  /// The server confirmed [batchId]: marks it and its photos completed, then
  /// deletes the photo files. The record is kept for the user's history.
  Future<void> markCompleted(String batchId);

  /// The upload of [batchId] failed: records [error], counts the attempt, and
  /// schedules the next automatic retry. Photos and records are kept.
  Future<void> markFailed(
    String batchId, {
    required String error,
    required DateTime nextAttemptAt,
  });

  /// Returns batches stuck in "uploading" since before [olderThan] (the app
  /// was killed mid-upload) to pending. Returns how many were recovered.
  Future<int> recoverInterruptedUploads({required DateTime olderThan});

  /// When the earliest failed batch may be retried, or null if none is waiting.
  Future<DateTime?> nextRetryAt();
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
