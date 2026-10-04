import 'dart:io';

/// How the mock upload server behaves. Chosen on the Pending Uploads screen
/// so every failure path can be demonstrated without a real backend.
enum MockServerMode {
  /// Uploads succeed after a realistic transfer time.
  normal,

  /// Bandwidth is so low that uploads time out.
  slowConnection,

  /// The server answers 503 Service Unavailable.
  serverError,

  /// About half of the uploads drop mid-transfer.
  unstable,
}

/// Keeps the chosen [MockServerMode] in a small file, so the background sync
/// worker (another isolate, with its own memory) uses the same mode as the app.
class MockServerSettings {
  MockServerSettings(this._file);

  final File _file;

  Future<MockServerMode> read() async {
    try {
      final name = (await _file.readAsString()).trim();
      return MockServerMode.values.asNameMap()[name] ?? MockServerMode.normal;
    } on PathNotFoundException {
      return MockServerMode.normal;
    }
  }

  Future<void> write(MockServerMode mode) async {
    await _file.writeAsString(mode.name, flush: true);
  }
}
