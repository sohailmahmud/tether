import 'package:equatable/equatable.dart';

import '../entities/retry_policy.dart';
import '../entities/upload_batch.dart';
import '../entities/upload_result.dart';
import '../repositories/upload_api.dart';
import '../repositories/upload_queue_repository.dart';

/// What a call to [ProcessUploadQueue] did.
class UploadRunSummary extends Equatable {
  const UploadRunSummary({
    this.uploaded = 0,
    this.failed = 0,
    this.stoppedOffline = false,
  });

  final int uploaded;
  final int failed;

  /// The run stopped early because there was no connection; the remaining
  /// batches were left for the next run.
  final bool stoppedOffline;

  UploadRunSummary operator +(UploadRunSummary other) => UploadRunSummary(
    uploaded: uploaded + other.uploaded,
    failed: failed + other.failed,
    stoppedOffline: stoppedOffline || other.stoppedOffline,
  );

  @override
  List<Object> get props => [uploaded, failed, stoppedOffline];
}

/// The upload engine: uploads every batch that is due, one at a time, and
/// records each outcome so nothing is lost.
///
/// - Success: the batch is completed and only then are its files deleted.
/// - Failure: files and records stay; the batch is retried after a backoff.
/// - No connection: the run stops, since every other batch would fail too.
///
/// Safe to trigger from many places at once. Overlapping calls in this isolate
/// join the run in progress (which then makes one more pass, so a batch
/// submitted mid-run isn't missed), and the repository's atomic claim stops a
/// worker in another isolate from taking the same batch.
class ProcessUploadQueue {
  ProcessUploadQueue({
    required this._queue,
    required this._api,
    this._clock = DateTime.now,
  });

  final UploadQueueRepository _queue;
  final UploadApi _api;
  final DateTime Function() _clock;

  Future<UploadRunSummary>? _running;
  bool _passRequested = false;
  bool _retryFailedRequested = false;

  /// Runs the engine. With [retryFailedNow], failed batches are retried
  /// straight away instead of waiting for their backoff ("Retry now").
  Future<UploadRunSummary> call({bool retryFailedNow = false}) {
    _passRequested = true;
    _retryFailedRequested |= retryFailedNow;
    return _running ??= _drain().whenComplete(() => _running = null);
  }

  Future<UploadRunSummary> _drain() async {
    var summary = const UploadRunSummary();
    while (_passRequested) {
      _passRequested = false;
      if (_retryFailedRequested) {
        _retryFailedRequested = false;
        await _queue.makeFailedDueNow(now: _clock());
      }
      summary += await _pass();
      if (summary.stoppedOffline) break;
    }
    _passRequested = false;
    _retryFailedRequested = false;
    return summary;
  }

  Future<UploadRunSummary> _pass() async {
    await _queue.recoverInterruptedUploads(
      olderThan: _clock().subtract(RetryPolicy.uploadLease),
    );
    var uploaded = 0;
    var failed = 0;
    // A batch that fails gets a retry time in the future, so it isn't claimed
    // again in this pass; the loop ends once nothing is due.
    while (true) {
      final batch = await _queue.claimNextDueBatch(now: _clock());
      if (batch == null) break;
      switch (await _upload(batch)) {
        case UploadSucceeded():
          await _queue.markCompleted(batch.id);
          uploaded++;
        case UploadFailed(:final reason, :final message):
          await _queue.markFailed(
            batch.id,
            error: message,
            nextAttemptAt: _clock().add(
              RetryPolicy.delayAfter(batch.retryCount + 1),
            ),
          );
          failed++;
          if (reason == UploadFailureReason.noConnection) {
            return UploadRunSummary(
              uploaded: uploaded,
              failed: failed,
              stoppedOffline: true,
            );
          }
      }
    }
    return UploadRunSummary(uploaded: uploaded, failed: failed);
  }

  /// An unexpected error from the API (a bug, not a network failure) still
  /// counts as a failed attempt, so the batch is kept and retried rather than
  /// left stuck in "uploading".
  Future<UploadResult> _upload(UploadBatch batch) async {
    try {
      return await _api.uploadBatch(batch);
    } on Object catch (_) {
      return const UploadFailed(
        UploadFailureReason.serverError,
        'Upload failed unexpectedly. It will be retried.',
      );
    }
  }
}
