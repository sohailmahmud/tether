import 'package:equatable/equatable.dart';

/// How far the upload of one batch has got.
final class UploadProgress extends Equatable {
  const UploadProgress({
    required this.batchId,
    required this.sentBytes,
    required this.totalBytes,
  });

  final String batchId;
  final int sentBytes;
  final int totalBytes;

  /// From 0 to 1.
  double get fraction =>
      totalBytes <= 0 ? 0 : (sentBytes / totalBytes).clamp(0, 1).toDouble();

  /// Whole percent, rounded down so 100% means everything was sent.
  int get percent => (fraction * 100).floor();

  @override
  List<Object> get props => [batchId, sentBytes, totalBytes];
}
