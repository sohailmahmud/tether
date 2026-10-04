import 'package:equatable/equatable.dart';

import '../../../domain/entities/upload_queue_snapshot.dart';

/// The local upload queue as the screens see it.
final class UploadQueueState extends Equatable {
  const UploadQueueState({
    this.isLoaded = false,
    this.queue = const UploadQueueSnapshot(),
    this.loadFailed = false,
    this.submitFailed = false,
  });

  /// False until the queue has been read from storage once.
  final bool isLoaded;
  final UploadQueueSnapshot queue;

  /// Storage could not be read; [queue] may be out of date.
  final bool loadFailed;

  /// The last "Upload batch" failed; cleared once the user has been told.
  final bool submitFailed;

  /// Photos taken for the batch being captured.
  int get draftPhotoCount => queue.draft?.photoCount ?? 0;

  /// Path of the newest photo in the draft, for the camera thumbnail.
  String? get latestDraftPhoto => queue.draft?.items.lastOrNull?.filePath;

  /// Submitted batches still waiting for the server.
  int get unfinishedBatchCount => queue.unfinished.length;

  UploadQueueState copyWith({
    UploadQueueSnapshot? queue,
    bool? isLoaded,
    bool? loadFailed,
    bool? submitFailed,
  }) => UploadQueueState(
    isLoaded: isLoaded ?? this.isLoaded,
    queue: queue ?? this.queue,
    loadFailed: loadFailed ?? this.loadFailed,
    submitFailed: submitFailed ?? this.submitFailed,
  );

  @override
  List<Object?> get props => [isLoaded, queue, loadFailed, submitFailed];
}
