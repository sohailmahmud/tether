import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/datasources/mock_server_settings.dart';
import '../data/datasources/mock_upload_api.dart';
import '../data/datasources/network_status.dart';
import '../data/datasources/photo_store.dart';
import '../data/datasources/upload_queue_database.dart';
import '../data/repositories/sqflite_upload_queue_repository.dart';
import '../domain/usecases/process_upload_queue.dart';

/// Everything the upload engine needs, built the same way in the app and in
/// the background worker's isolate, so both behave identically.
class SyncDependencies {
  SyncDependencies._({
    required this.uploadQueue,
    required this.mockServerSettings,
    required this.network,
    required this.processUploadQueue,
  });

  /// [onQueueWrite] is called after every change this isolate makes to the
  /// queue; the background worker uses it to notify the app's isolate.
  static Future<SyncDependencies> open({void Function()? onQueueWrite}) async {
    final documents = await getApplicationDocumentsDirectory();
    final uploadQueue = SqfliteUploadQueueRepository(
      database: await UploadQueueDatabase.open(
        p.join(await getDatabasesPath(), UploadQueueDatabase.fileName),
      ),
      photos: PhotoStore(Directory(p.join(documents.path, 'photos'))),
      onWrite: onQueueWrite,
    );
    final mockServerSettings = MockServerSettings(
      File(p.join(documents.path, 'mock_server_mode.txt')),
    );
    final network = NetworkStatus();
    return SyncDependencies._(
      uploadQueue: uploadQueue,
      mockServerSettings: mockServerSettings,
      network: network,
      processUploadQueue: ProcessUploadQueue(
        queue: uploadQueue,
        // The assessment provides no API; see MockUploadApi.
        api: MockUploadApi(
          mode: mockServerSettings.read,
          isOnline: network.isOnline,
        ),
      ),
    );
  }

  final SqfliteUploadQueueRepository uploadQueue;
  final MockServerSettings mockServerSettings;
  final NetworkStatus network;
  final ProcessUploadQueue processUploadQueue;
}
