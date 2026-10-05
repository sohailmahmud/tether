# Architecture Decision Records

Significant decisions are recorded here, each with its context, the decision, its consequences and the alternatives considered.

| ADR | Decision |
|---|---|
| [0001](0001-two-applications-one-per-task.md) | Two independent apps, one per task, each with its own build, CI and APK |
| [0002](0002-unidirectional-state-management.md) | One `StateFlow` per screen on Android; one Cubit per concern on Flutter |
| [0003](0003-geofence-eligibility-policy.md) | One domain policy for distance, accuracy and freshness, re-validated at the moment of the tap |
| [0004](0004-sqlite-upload-queue.md) | SQLite as the upload queue's system of record |
| [0005](0005-exactly-once-processing.md) | Atomic claims, leases, guarded failures and idempotency keys for exactly-once processing |
| [0006](0006-sync-orchestration.md) | Foreground triggers plus a constrained WorkManager task running the same engine |
| [0007](0007-api-boundary-and-mock-server.md) | A typed `UploadApi` contract with progress; a mock server with selectable failure modes |
| [0008](0008-composition-roots-and-manual-di.md) | Manual dependency injection through explicit composition roots |
| [0009](0009-security-privacy-and-release.md) | Least privilege, no cloud backup, no secrets in version control |
