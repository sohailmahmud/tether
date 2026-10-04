import 'package:sqflite/sqflite.dart';

/// Schema and opening of the upload queue's SQLite database.
abstract final class UploadQueueDatabase {
  static const fileName = 'upload_queue.db';
  static const _version = 1;

  static const batches = 'upload_batches';
  static const items = 'upload_items';

  /// Opens (creating if needed) the database at [path]. [factory] lets tests
  /// use an in-process SQLite instead of the platform plugin.
  static Future<Database> open(
    String path, {
    DatabaseFactory? factory,
  }) => (factory ?? databaseFactory).openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: _version,
      // Off by default in SQLite; without it a photo row could outlive its batch.
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _create,
    ),
  );

  static Future<void> _create(Database db, int version) async {
    final batch = db.batch()
      ..execute('''
        CREATE TABLE $batches (
          id           TEXT PRIMARY KEY,
          created_at   INTEGER NOT NULL,
          status       TEXT NOT NULL
                       CHECK (status IN ('draft', 'pending', 'uploading', 'failed', 'completed')),
          retry_count  INTEGER NOT NULL DEFAULT 0,
          last_error   TEXT,
          submitted_at INTEGER,
          updated_at   INTEGER NOT NULL
        )''')
      // At most one batch can be the open draft that new photos go into.
      ..execute(
        "CREATE UNIQUE INDEX one_draft_batch ON $batches (status) WHERE status = 'draft'",
      )
      ..execute(
        'CREATE INDEX batches_by_status ON $batches (status, created_at)',
      )
      ..execute('''
        CREATE TABLE $items (
          id          TEXT PRIMARY KEY,
          batch_id    TEXT NOT NULL REFERENCES $batches (id) ON DELETE CASCADE,
          file_path   TEXT NOT NULL,
          status      TEXT NOT NULL
                      CHECK (status IN ('pending', 'uploading', 'failed', 'completed')),
          retry_count INTEGER NOT NULL DEFAULT 0,
          size_bytes  INTEGER NOT NULL,
          created_at  INTEGER NOT NULL
        )''')
      ..execute('CREATE INDEX items_by_batch ON $items (batch_id, created_at)');
    await batch.commit(noResult: true);
  }
}
