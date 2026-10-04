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

  final Future<MockServerMode> Function() _mode;
  final Future<bool> Function() _isOnline;
  final Random _random;
  final Future<void> Function(Duration) _wait;

  /// Batches the "server" has stored, by id. Re-sending one returns the same
  /// receipt instead of storing it twice: the idempotency the real API needs.
  final _received = <String, String>{};

  @override
  Future<UploadResult> uploadBatch(UploadBatch batch) async {
    if (!await _isOnline()) {
      await _wait(const Duration(milliseconds: 300));
      return const UploadFailed(
        UploadFailureReason.noConnection,
        'No internet connection.',
      );
    }
    final alreadyStored = _received[batch.id];
    if (alreadyStored != null) return UploadSucceeded(receiptId: alreadyStored);

    switch (await _mode()) {
      case MockServerMode.normal:
        await _wait(_transferTime(batch, normalBytesPerSecond));
        return _store(batch);
      case MockServerMode.slowConnection:
        final transfer = _transferTime(batch, slowBytesPerSecond);
        if (transfer <= timeout) {
          await _wait(transfer);
          return _store(batch);
        }
        await _wait(timeout);
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
          await _wait(transfer);
          return _store(batch);
        }
        // Drops part-way through the transfer.
        await _wait(transfer * 0.5);
        return const UploadFailed(
          UploadFailureReason.timeout,
          'The connection dropped during the upload.',
        );
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
