import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tether_capture/data/datasources/mock_server_settings.dart';
import 'package:tether_capture/data/datasources/mock_upload_api.dart';
import 'package:tether_capture/domain/entities/upload_result.dart';

import '../helpers/fake_upload_queue_repository.dart';

void main() {
  var mode = MockServerMode.normal;
  var online = true;
  late List<Duration> waits;
  late MockUploadApi api;

  setUp(() {
    mode = MockServerMode.normal;
    online = true;
    waits = [];
    api = MockUploadApi(
      mode: () async => mode,
      isOnline: () async => online,
      random: Random(1),
      wait: (duration) async => waits.add(duration),
    );
  });

  // Three 512 KB photos = 1.5 MB.
  final batch = testBatch(id: 'b1', photos: 3);

  test('normal: succeeds after a transfer time based on size', () async {
    final result = await api.uploadBatch(batch);

    expect(result, isA<UploadSucceeded>());
    expect(waits.single, const Duration(milliseconds: 750)); // 1.5 MB at 2 MB/s
  });

  test('offline: fails as no connection, whatever the mode', () async {
    online = false;

    final result = await api.uploadBatch(batch) as UploadFailed;

    expect(result.reason, UploadFailureReason.noConnection);
  });

  test('slow connection: times out on a real photo batch', () async {
    mode = MockServerMode.slowConnection;

    final result = await api.uploadBatch(batch) as UploadFailed;

    expect(result.reason, UploadFailureReason.timeout);
    expect(waits.single, MockUploadApi.timeout);
  });

  test('server error: fails with a server error', () async {
    mode = MockServerMode.serverError;

    final result = await api.uploadBatch(batch) as UploadFailed;

    expect(result.reason, UploadFailureReason.serverError);
    expect(result.message, contains('503'));
  });

  test('unstable: some uploads drop, others get through', () async {
    mode = MockServerMode.unstable;
    final results = [
      for (var i = 0; i < 20; i++) await api.uploadBatch(testBatch(id: 'b$i')),
    ];

    expect(results.whereType<UploadSucceeded>(), isNotEmpty);
    expect(results.whereType<UploadFailed>(), isNotEmpty);
  });

  test(
    're-sending a stored batch returns the same receipt instead of storing it twice',
    () async {
      final first = await api.uploadBatch(batch) as UploadSucceeded;
      mode =
          MockServerMode.serverError; // even a failing server knows it has it

      final again = await api.uploadBatch(batch) as UploadSucceeded;

      expect(again.receiptId, first.receiptId);
      expect(waits, hasLength(1), reason: 'no second transfer');
    },
  );

  group('settings file', () {
    late Directory temp;

    setUp(
      () async => temp = await Directory.systemTemp.createTemp('mock_server'),
    );
    tearDown(() => temp.delete(recursive: true));

    test('defaults to normal, and remembers the choice', () async {
      final settings = MockServerSettings(File(p.join(temp.path, 'mode.txt')));
      expect(await settings.read(), MockServerMode.normal);

      await settings.write(MockServerMode.slowConnection);

      final reopened = MockServerSettings(File(p.join(temp.path, 'mode.txt')));
      expect(await reopened.read(), MockServerMode.slowConnection);
    });

    test('an unreadable value falls back to normal', () async {
      final file = File(p.join(temp.path, 'mode.txt'))
        ..writeAsStringSync('nonsense');

      expect(await MockServerSettings(file).read(), MockServerMode.normal);
    });
  });
}
