import 'dart:async';
import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/retry_policy.dart';
import '../../../domain/entities/upload_progress.dart';
import '../../../domain/repositories/background_sync_scheduler.dart';
import '../../../domain/repositories/upload_queue_repository.dart';
import '../../../domain/usecases/process_upload_queue.dart';

final class SyncState extends Equatable {
  const SyncState({
    this.isOnline = true,
    this.isSyncing = false,
    this.lastRun,
    this.lastRunFailed = false,
    this.progress = const {},
  });

  /// Whether the device has a network connection.
  final bool isOnline;
  final bool isSyncing;

  /// What the most recent run did; null before the first run finishes.
  final UploadRunSummary? lastRun;

  /// The last run hit an unexpected storage error. The queue is untouched
  /// and the next trigger tries again.
  final bool lastRunFailed;

  /// Bytes sent so far, by batch id, for the batches this app is uploading
  /// right now. Uploads run by the background worker happen in another
  /// isolate and don't appear here.
  final Map<String, UploadProgress> progress;

  SyncState copyWith({
    bool? isOnline,
    bool? isSyncing,
    UploadRunSummary? lastRun,
    bool? lastRunFailed,
    Map<String, UploadProgress>? progress,
  }) => SyncState(
    isOnline: isOnline ?? this.isOnline,
    isSyncing: isSyncing ?? this.isSyncing,
    lastRun: lastRun ?? this.lastRun,
    lastRunFailed: lastRunFailed ?? this.lastRunFailed,
    progress: progress ?? this.progress,
  );

  @override
  List<Object?> get props => [
    isOnline,
    isSyncing,
    lastRun,
    lastRunFailed,
    progress,
  ];
}

/// Decides when the upload engine runs while the app is open, and hands
/// over to the background worker for when it isn't.
///
/// Automatic triggers, no user action needed:
/// - the app starting;
/// - the connection returning and staying up for [stableConnectionDelay]
///   (failed batches are retried at once, skipping their backoff);
/// - the next retry time of a failed batch arriving.
///
/// Manual: "Upload batch" and "Retry now".
class SyncCubit extends Cubit<SyncState> {
  SyncCubit({
    required this._processQueue,
    required this._queue,
    required this._backgroundSync,
    required this._onlineChanges,
    required this._isOnline,
    this._clock = DateTime.now,
  }) : super(const SyncState()) {
    _progress = _processQueue.progress.listen(
      (update) => _emit(
        state.copyWith(progress: {...state.progress, update.batchId: update}),
      ),
    );
  }

  /// How long a connection must stay up before uploads resume, so a
  /// flapping network doesn't set off a burst of failing attempts.
  static const stableConnectionDelay = Duration(seconds: 3);

  /// After an unexpected storage error, the next run waits at least this
  /// long, so a lasting fault (e.g. a full disk) can't spin in a busy loop.
  static const errorRetryDelay = RetryPolicy.firstDelay;

  final ProcessUploadQueue _processQueue;
  final UploadQueueRepository _queue;
  final BackgroundSyncScheduler _backgroundSync;
  final Stream<bool> _onlineChanges;
  final Future<bool> Function() _isOnline;
  final DateTime Function() _clock;

  StreamSubscription<bool>? _connectivity;
  late final StreamSubscription<UploadProgress> _progress;
  Timer? _stableConnectionTimer;
  Timer? _retryTimer;

  /// Called once when the app starts: watches connectivity and uploads
  /// whatever is left from last time.
  Future<void> start() async {
    _connectivity = _onlineChanges.listen(_onConnectivityChanged);
    _emit(state.copyWith(isOnline: await _isOnline()));
    await sync();
  }

  /// Uploads everything due. [retryFailedNow] skips the backoff wait of
  /// failed batches. Overlapping calls share one engine run.
  Future<void> sync({bool retryFailedNow = false}) async {
    _retryTimer?.cancel();
    _emit(state.copyWith(isSyncing: true, lastRunFailed: false));
    await _handOverToBackground();
    var runFailed = false;
    try {
      final summary = await _processQueue(retryFailedNow: retryFailedNow);
      // Every batch the run took on is now completed or failed.
      _emit(
        state.copyWith(isSyncing: false, lastRun: summary, progress: const {}),
      );
    } on Object catch (error, stack) {
      runFailed = true;
      developer.log(
        'Upload run failed',
        name: 'Sync',
        error: error,
        stackTrace: stack,
      );
      _emit(
        state.copyWith(
          isSyncing: false,
          lastRunFailed: true,
          progress: const {},
        ),
      );
    }
    await _scheduleNextRetry(afterError: runFailed);
  }

  void _onConnectivityChanged(bool online) {
    final wasOnline = state.isOnline;
    _emit(state.copyWith(isOnline: online));
    _stableConnectionTimer?.cancel();
    if (online && !wasOnline) {
      _stableConnectionTimer = Timer(
        stableConnectionDelay,
        () => unawaited(sync(retryFailedNow: true)),
      );
    } else if (!online) {
      // Nothing can upload while offline; reconnecting triggers the retry.
      _retryTimer?.cancel();
    }
  }

  /// While anything is unfinished, keep a background run scheduled, so
  /// uploads finish even if the app is closed first. The task is unique, so
  /// scheduling again is cheap.
  Future<void> _handOverToBackground() async {
    try {
      if (await _queue.hasUnfinishedUploads()) {
        await _backgroundSync.scheduleUpload();
      }
    } on Object catch (error, stack) {
      // The foreground run still goes ahead; the next run schedules again.
      developer.log(
        'Background sync not scheduled',
        name: 'Sync',
        error: error,
        stackTrace: stack,
      );
    }
  }

  /// Runs again when the earliest failed batch is due, if online. After a
  /// storage error, runs again in [errorRetryDelay] at the earliest, and
  /// even if no failed batch is waiting, since the error may have hidden one.
  Future<void> _scheduleNextRetry({required bool afterError}) async {
    if (isClosed || !state.isOnline) return;
    DateTime? next;
    try {
      next = await _queue.nextRetryAt();
    } on Object {
      if (!afterError) return;
    }
    if (afterError) {
      final earliest = _clock().add(errorRetryDelay);
      if (next == null || next.isBefore(earliest)) next = earliest;
    }
    _retryTimer?.cancel();
    if (next == null || isClosed) return;
    final wait = next.difference(_clock());
    _retryTimer = Timer(
      wait.isNegative ? Duration.zero : wait,
      () => unawaited(sync()),
    );
  }

  @override
  Future<void> close() async {
    _stableConnectionTimer?.cancel();
    _retryTimer?.cancel();
    await _connectivity?.cancel();
    await _progress.cancel();
    return super.close();
  }

  void _emit(SyncState next) {
    if (!isClosed) emit(next);
  }
}
