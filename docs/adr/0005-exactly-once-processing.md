# ADR-0005: Exactly-once processing with claims, leases and idempotency

- **Status:** Accepted
- **Scope:** Tether Capture upload engine (`ProcessUploadQueue`) and queue repository

## Context

Uploads can be started by the app and by the background worker, sometimes at the same moment. The process can die mid-upload, and networks fail half-way through a transfer. The system must never lose a photo, never upload a batch twice, and never let a stale attempt overwrite a newer outcome.

## Decision

| Mechanism | Guarantee |
|---|---|
| **Atomic claim:** select and update inside one exclusive transaction, with an update conditional on the status just read | Only one worker can move a batch to *uploading* |
| **Lease:** an *uploading* claim older than 5 minutes returns to *pending* | Uploads interrupted by process death are recovered |
| **Guarded failure:** a failure is recorded only while the batch is still *uploading* | A late failure can't overwrite a batch that another run has completed |
| **Delete after commit:** files are removed only after *completed* is committed | No data loss on a crash between the two steps |
| **Idempotency key:** the batch id is sent with every upload | A re-sent batch can't be stored twice by the server |
| **Orphan sweep at launch:** run in the app's isolate only | Leftovers of an unlucky process kill are cleaned up |

## Consequences

**Positive:**
- **Delivery semantics:** at-least-once delivery to an idempotent server gives effectively exactly-once storage.
- **Verified by mutation:** each guarantee has a test that fails if the mechanism is removed. Without the atomic claim, two concurrent workers produce 12 claims for 6 batches.

**Negative:**
- The guarantee depends on the server honouring the idempotency key. This is part of the `UploadApi` contract (see [ADR-0007](0007-api-boundary-and-mock-server.md)).
- An upload that genuinely runs longer than the lease could be claimed twice. The 5-minute lease is far beyond the 8 s request timeout, and the guarded failure and idempotency key keep the outcome correct anyway.
