import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/usecases/process_upload_queue.dart';

final class SyncState extends Equatable {
  const SyncState({
    this.isSyncing = false,
    this.lastRun,
    this.lastRunFailed = false,
  });

  final bool isSyncing;

  /// What the most recent run did; null before the first run finishes.
  final UploadRunSummary? lastRun;

  /// The last run hit an unexpected storage error. The queue is untouched
  /// and the next trigger tries again.
  final bool lastRunFailed;

  @override
  List<Object?> get props => [isSyncing, lastRun, lastRunFailed];
}

/// Runs the upload engine when something should trigger an upload: the app
/// starting, a batch being submitted, or the user tapping "Retry now".
/// Upload progress per batch comes from the queue itself.
class SyncCubit extends Cubit<SyncState> {
  SyncCubit(this._processQueue) : super(const SyncState());

  final ProcessUploadQueue _processQueue;

  /// Uploads everything due. [retryFailedNow] skips the backoff wait of
  /// failed batches. Overlapping calls share one engine run.
  Future<void> sync({bool retryFailedNow = false}) async {
    _emit(SyncState(isSyncing: true, lastRun: state.lastRun));
    try {
      final summary = await _processQueue(retryFailedNow: retryFailedNow);
      _emit(SyncState(lastRun: summary));
    } on Object catch (error, stack) {
      developer.log(
        'Upload run failed',
        name: 'Sync',
        error: error,
        stackTrace: stack,
      );
      _emit(SyncState(lastRun: state.lastRun, lastRunFailed: true));
    }
  }

  void _emit(SyncState next) {
    if (!isClosed) emit(next);
  }
}
