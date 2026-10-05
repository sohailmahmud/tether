# ADR-0007: API boundary and mock server

- **Status:** Accepted
- **Scope:** Tether Capture domain contract and data layer

## Context

The brief provides no backend and explicitly allows mocked success and failure responses. The sync engine still has to be proven against realistic failures: no internet, low bandwidth, server errors and dropped connections.

## Decision

The domain defines an `UploadApi` contract:

- **Request:** `uploadBatch(batch, onProgress)` uploads one batch. The batch id is an **idempotency key**.
- **Results:** expected failures are returned as typed results (`UploadFailed` with `noConnection`, `timeout` or `serverError`), not thrown.
- **Progress:** reported as bytes sent, as often as the transport can measure it.

`MockUploadApi` implements the contract in the data layer:

| Behaviour | Detail |
|---|---|
| Real connectivity | No network means "No internet connection", whatever the mode |
| Selectable modes | Normal (about 2 MB/s), slow connection (about 16 KB/s with an 8 s timeout), server error (503) and unstable (about half of uploads drop part-way) |
| Shared mode | Stored in a settings file, so the background worker uses the same mode |
| Progress | Reported every 100 ms. A timeout or a dropped connection stops at the fraction actually sent |
| Idempotency | Re-sending a stored batch returns its original receipt |

## Consequences

**Positive:**
- Every success and failure path can be demonstrated on a device without a backend.
- Replacing the mock with a real HTTP client changes one data-layer class. For example, a multipart upload with `onSendProgress` maps directly onto `onProgress`.

**Negative:**
- The mock's idempotency record lives in memory, separately in each isolate. A real server would persist it.
