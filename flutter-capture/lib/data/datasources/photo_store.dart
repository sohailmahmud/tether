import 'dart:io';

import 'package:path/path.dart' as p;

/// Keeps captured photos in app storage under [root].
///
/// The camera writes to the cache directory, which Android may clear at any
/// time, so queued photos are moved out of it.
class PhotoStore {
  PhotoStore(this.root);

  /// Usually `<app documents>/photos`.
  final Directory root;

  /// Moves [sourcePath] to `<root>/<batchId>/<itemId>.<ext>` and returns that
  /// path relative to [root]. Relative paths stay valid if the app's storage
  /// location changes, e.g. after restoring on a new device.
  Future<String> keep(
    String sourcePath, {
    required String batchId,
    required String itemId,
  }) async {
    final extension = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final relative = p.join(batchId, '$itemId$extension');
    final target = File(absolutePath(relative));
    await target.parent.create(recursive: true);
    final source = File(sourcePath);
    try {
      // Same file system: an atomic rename, no copying.
      await source.rename(target.path);
    } on FileSystemException {
      // Different file systems: copy, then remove the original.
      await source.copy(target.path);
      await source.delete();
    }
    return relative;
  }

  String absolutePath(String relativePath) => p.join(root.path, relativePath);

  /// Deletes a kept photo. Missing files are ignored.
  Future<void> delete(String relativePath) async {
    try {
      await File(absolutePath(relativePath)).delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }
}
