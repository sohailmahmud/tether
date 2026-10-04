import 'package:sqflite/sqflite.dart';

/// Schema and opening of the upload queue's SQLite database.
///
/// Versions:
/// 1. Batches and photos.
/// 2. `next_attempt_at` on batches, for retry backoff.
abstract final class UploadQueueDatabase {
  static const fileName = 'upload_queue.db';
  static const version = 2;

  static const batches = 'upload_batches';
  static const items = 'upload_items';

  /// Opens (creating or upgrading if needed) the database at [path].
  ///
  /// On Android, sqflite keeps one native connection per database file for
  /// the whole process, so the app and the background sync worker (another
  /// isolate) share it, and the plugin queues other isolates' calls while a
  /// transaction is open. [factory] lets tests use an in-process SQLite;
  /// [targetVersion] lets them create an older schema to test upgrades.
  static Future<Database> open(
    String path, {
    DatabaseFactory? factory,
    int targetVersion = version,
  }) => (factory ?? databaseFactory).openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: targetVersion,
      onConfigure: (db) async {
        // Off by default in SQLite; without it a photo row could outlive its batch.
        await db.execute('PRAGMA foreign_keys = ON');
        // Should another connection to the file ever exist (e.g. a separate
        // process), wait for its write instead of failing with "locked".
        await db.rawQuery('PRAGMA busy_timeout = 5000');
      },
      onCreate: (db, version) async {
        await _createV1(db);
        await _upgrade(db, 1, version);
      },
      onUpgrade: _upgrade,
    ),
  );

  static Future<void> _createV1(Database db) async {
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

  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2 && to >= 2) {
      // Earliest time a failed batch may be retried; null means "now".
      await db.execute(
        'ALTER TABLE $batches ADD COLUMN next_attempt_at INTEGER',
      );
    }
  }
}
