import 'dart:isolate';
import 'dart:ui';

/// Carries "the upload queue changed" from the background worker's isolate
/// to the app's, so open screens reload instead of showing stale state.
///
/// On Android, WorkManager runs the worker in the app's process, and
/// `IsolateNameServer` reaches every isolate in the process. If the app
/// isn't running, there is no listener; it reads the queue fresh on launch.
abstract final class QueueChangeChannel {
  static const _portName = 'tether.upload_queue.changes';

  /// In the app's isolate: calls [onChange] whenever another isolate
  /// announces a change. Close the returned port to stop listening.
  static ReceivePort listen(void Function() onChange) {
    final port = ReceivePort();
    // A previous app isolate in this process may have left its port behind.
    IsolateNameServer.removePortNameMapping(_portName);
    IsolateNameServer.registerPortWithName(port.sendPort, _portName);
    port.listen((_) => onChange());
    return port;
  }

  /// In the background worker: tells the app's isolate, if it is running.
  static void announce() =>
      IsolateNameServer.lookupPortByName(_portName)?.send(null);
}
