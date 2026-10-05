import 'dart:async';

import 'package:tether_capture/domain/entities/upload_batch.dart';
import 'package:tether_capture/domain/entities/upload_result.dart';
import 'package:tether_capture/domain/repositories/upload_api.dart';

/// [UploadApi] that answers from a script and records every call.
class FakeUploadApi implements UploadApi {
  /// Results handed out in order; after the script runs out, success.
  final List<UploadResult> script = [];

  /// When set, each upload waits for it.
  Completer<void>? gate;

  /// When set, uploadBatch throws it (a bug, not a network failure).
  Object? throws;

  /// Fractions of the batch reported as sent, in order, before [gate].
  List<double> progressSteps = [];

  final List<String> uploadedIds = [];

  static const noConnection = UploadFailed(
    UploadFailureReason.noConnection,
    'No internet connection.',
  );
  static const serverError = UploadFailed(
    UploadFailureReason.serverError,
    'Server error (503).',
  );

  @override
  Future<UploadResult> uploadBatch(
    UploadBatch batch, {
    UploadProgressCallback? onProgress,
  }) async {
    uploadedIds.add(batch.id);
    for (final fraction in progressSteps) {
      onProgress?.call((batch.totalBytes * fraction).round(), batch.totalBytes);
    }
    await gate?.future;
    final error = throws;
    if (error != null) throw error;
    return script.isEmpty
        ? UploadSucceeded(receiptId: 'rcpt-${batch.id}')
        : script.removeAt(0);
  }
}
