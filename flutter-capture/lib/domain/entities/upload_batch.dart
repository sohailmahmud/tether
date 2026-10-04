import 'package:equatable/equatable.dart';

import 'upload_item.dart';
import 'upload_status.dart';

/// Photos captured together and uploaded together.
class UploadBatch extends Equatable {
  const UploadBatch({
    required this.id,
    required this.createdAt,
    required this.status,
    required this.retryCount,
    required this.items,
    this.lastError,
    this.submittedAt,
    this.nextAttemptAt,
  });

  final String id;
  final DateTime createdAt;
  final UploadStatus status;

  /// Failed upload attempts so far.
  final int retryCount;

  /// Why the last attempt failed, for display; null if none has failed.
  final String? lastError;

  /// When the user sent the batch for upload; null while it is a draft.
  final DateTime? submittedAt;

  /// Earliest automatic retry after a failure; null when not waiting.
  final DateTime? nextAttemptAt;

  /// Photos in capture order.
  final List<UploadItem> items;

  int get photoCount => items.length;

  int get totalBytes => items.fold(0, (sum, item) => sum + item.sizeBytes);

  @override
  List<Object?> get props => [
    id,
    createdAt,
    status,
    retryCount,
    lastError,
    submittedAt,
    nextAttemptAt,
    items,
  ];
}
