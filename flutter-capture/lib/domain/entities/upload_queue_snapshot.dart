import 'package:equatable/equatable.dart';

import 'upload_batch.dart';
import 'upload_status.dart';

/// The whole local queue at one moment.
class UploadQueueSnapshot extends Equatable {
  const UploadQueueSnapshot({this.draft, this.batches = const []});

  /// The batch currently being captured, if any photo has been taken for it.
  final UploadBatch? draft;

  /// Submitted batches, newest first.
  final List<UploadBatch> batches;

  /// Submitted batches not yet confirmed by the server.
  List<UploadBatch> get unfinished =>
      batches.where((b) => b.status != UploadStatus.completed).toList();

  @override
  List<Object?> get props => [draft, batches];
}
