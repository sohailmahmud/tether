import 'package:tether_capture/domain/repositories/background_sync_scheduler.dart';

class FakeBackgroundSyncScheduler implements BackgroundSyncScheduler {
  int scheduleCount = 0;

  /// When set, scheduleUpload() throws it.
  Object? throws;

  @override
  Future<void> scheduleUpload() async {
    final error = throws;
    if (error != null) throw error;
    scheduleCount++;
  }
}
