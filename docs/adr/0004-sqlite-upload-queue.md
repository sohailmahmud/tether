# ADR-0004: SQLite as the upload queue store

- **Status:** Accepted
- **Scope:** Tether Capture data layer

## Context

The upload queue is the system of record for captured photos until the server confirms them. It must:

- Survive process death and device restarts.
- Change batch and photo statuses together (atomic multi-row transitions).
- Be shared safely between the app's isolate and the background worker's isolate.
- Support versioned schema migrations.

## Decision

Use SQLite through `sqflite`, with an explicit schema:

- **Tables:** `upload_batches` and `upload_items`. Foreign keys are enabled on every connection, and `CHECK` constraints validate status values.
- **One draft batch:** a partial unique index allows only one batch being captured at a time.
- **Migrations:** versioned and run in place. v1 → v2 is tested, and was verified on a device with a populated queue.
- **Photo files:** stored outside the database under `photos/<batch>/`, referenced by relative paths that survive storage relocation.

## Consequences

**Positive:**
- ACID transactions back the exactly-once claim (see [ADR-0005](0005-exactly-once-processing.md)).
- On Android, sqflite shares one native connection per database file across isolates and serializes their transactions. This was confirmed in the plugin source and covered by a concurrent-claim test.
- The data is inspectable with standard tools.

**Negative:**
- SQL and row mapping are hand-written. Real-SQL tests (`sqflite_common_ffi`) cover every operation, including restart and upgrade.

## Alternatives considered

| Option | Why not |
|---|---|
| Hive | No multi-row transactions and no multi-isolate support |
| Isar | Uncertain long-term maintenance; continues only as a community fork |
| Drift | The same SQLite engine, plus code generation, which a two-table schema doesn't need |
| JSON files or key-value storage | No atomic multi-record updates |
