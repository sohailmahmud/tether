import 'package:equatable/equatable.dart';

import 'upload_status.dart';

/// One photo in an upload batch, stored in app storage.
class UploadItem extends Equatable {
  const UploadItem({
    required this.id,
    required this.batchId,
    required this.filePath,
    required this.status,
    required this.retryCount,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String id;
  final String batchId;

  /// Absolute path of the photo file in app storage.
  final String filePath;
  final UploadStatus status;

  /// Failed upload attempts so far.
  final int retryCount;
  final DateTime createdAt;
  final int sizeBytes;

  @override
  List<Object?> get props => [
    id,
    batchId,
    filePath,
    status,
    retryCount,
    createdAt,
    sizeBytes,
  ];
}
