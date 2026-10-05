import 'dart:math';

import '../../domain/entities/upload_batch.dart';
import '../../domain/entities/upload_result.dart';
import '../../domain/repositories/upload_api.dart';
import 'mock_server_settings.dart';

/// Stand-in for the real upload endpoint, which the assessment doesn't
/// provide. Simulates transfer time from batch size and bandwidth, and fails
/// in the ways [MockServerMode] selects.
///
/// It honours the device's real connectivity: in airplane mode every upload
/// fails with "No internet connection", whatever the mode.
class MockUploadApi implements UploadApi {
  MockUploadApi({
    required this._mode,
    required this._isOnline,
    Random? random,
    this._wait = Future<void>.delayed,
  }) : _random = random ?? Random();

  /// Gives up on a request after this long, like an HTTP client timeout.
  static const timeout = Duration(seconds: 8);

  /// Simulated bandwidth for [MockServerMode.normal]: about 2 MB/s.
  static const normalBytesPerSecond = 2 * 1024 * 1024;

  /// Simulated bandwidth for [MockServerMode.slowConnection]: about 16 KB/s,
  /// so a single 1080p photo already takes longer than [timeout].
  static const slowBytesPerSecond = 16 * 1024;

  /// How often upload progress is reported during a transfer.
  static const progressInterval = Duration(milliseconds: 100);

  final Future<MockServerMode> Function() _mode;
  final Future<bool> Function() _isOnline;
  final Random _random;
  final Future<void> Function(Duration) _wait;

  /// Batches the "server" has stored, by id. Re-sending one returns the same
  /// receipt instead of storing it twice: the idempotency the real API needs.
  final _received = <String, String>{};

  @override
  Future<UploadResult> uploadBatch(
    UploadBatch batch, {
    UploadProgressCallback? onProgress,
  }) async {
    if (!await _isOnline()) {
      await _wait(const Duration(milliseconds: 300));
      return const UploadFailed(
        UploadFailureReason.noConnection,
        'No internet connection.',
      );
    }
    final alreadyStored = _received[batch.id];
    if (alreadyStored != null) {
      onProgress?.call(batch.totalBytes, batch.totalBytes);
      return UploadSucceeded(receiptId: alreadyStored);
    }

    switch (await _mode()) {
      case MockServerMode.normal:
        await _send(
          batch,
          _transferTime(batch, normalBytesPerSecond),
          onProgress,
        );
        return _store(batch);
      case MockServerMode.slowConnection:
        final transfer = _transferTime(batch, slowBytesPerSecond);
        if (transfer <= timeout) {
          await _send(batch, transfer, onProgress);
          return _store(batch);
        }
        await _send(batch, transfer, onProgress, stopAfter: timeout);
        return const UploadFailed(
          UploadFailureReason.timeout,
          'Timed out: the connection is too slow.',
        );
      case MockServerMode.serverError:
        await _wait(const Duration(milliseconds: 600));
        return const UploadFailed(
          UploadFailureReason.serverError,
          'Server error (503 Service Unavailable).',
        );
      case MockServerMode.unstable:
        final transfer = _transferTime(batch, normalBytesPerSecond);
        if (_random.nextBool()) {
          await _send(batch, transfer, onProgress);
          return _store(batch);
        }
        // Drops part-way through the transfer.
        await _send(batch, transfer, onProgress, stopAfter: transfer * 0.5);
        return const UploadFailed(
          UploadFailureReason.timeout,
          'The connection dropped during the upload.',
        );
    }
  }

  /// Simulates sending [batch] at a speed where all of it takes
  /// [fullTransfer], giving up after [stopAfter] if set. Reports the bytes
  /// sent about every [progressInterval].
  Future<void> _send(
    UploadBatch batch,
    Duration fullTransfer,
    UploadProgressCallback? onProgress, {
    Duration? stopAfter,
  }) async {
    final total = batch.totalBytes;
    final end = stopAfter ?? fullTransfer;
    final steps = max(
      1,
      (end.inMicroseconds / progressInterval.inMicroseconds).ceil(),
    );
    var elapsed = 0;
    for (var step = 1; step <= steps; step++) {
      // Step boundaries in whole microseconds, so the waits add up exactly.
      final next = end.inMicroseconds * step ~/ steps;
      await _wait(Duration(microseconds: next - elapsed));
      elapsed = next;
      onProgress?.call(total * elapsed ~/ fullTransfer.inMicroseconds, total);
    }
  }

  UploadResult _store(UploadBatch batch) {
    final receipt = 'rcpt-${batch.id}';
    _received[batch.id] = receipt;
    return UploadSucceeded(receiptId: receipt);
  }

  /// At least half a second, so even tiny batches are visibly "uploading".
  static Duration _transferTime(UploadBatch batch, int bytesPerSecond) {
    final millis = batch.totalBytes * 1000 ~/ bytesPerSecond;
    return Duration(milliseconds: max(500, millis));
  }
}
