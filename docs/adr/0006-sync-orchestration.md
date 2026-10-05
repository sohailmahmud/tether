# ADR-0006: Sync orchestration with foreground triggers and WorkManager

- **Status:** Accepted
- **Scope:** Tether Capture synchronization

## Context

The brief requires a background worker that monitors connectivity, keeps failed uploads queued, and retries automatically once a stable connection is detected, without user intervention.

Android limits background execution, and the open app should react immediately rather than waiting for a scheduler.

## Decision

Two cooperating layers run the **same** engine (`ProcessUploadQueue`, built by `SyncDependencies`).

**Foreground: `SyncCubit`, while the app is open.** It triggers a run:
- on launch
- when the connection returns and stays up for 3 s, which absorbs a flapping network
- when a failed batch's retry time arrives (exponential backoff, 30 s doubling, capped at 15 min; paused while offline)
- after **Upload batch** and **Retry now**

**Background: a unique one-off WorkManager task.**
- **Configuration:** "keep" policy, *network connected* constraint, exponential backoff from 30 s.
- **Lifetime:** it is kept scheduled while any batch is unfinished, and runs in its own isolate even after the app is closed.
- **Hand-off:** writes made by the worker are announced to the app's isolate over `IsolateNameServer`, so open screens stay current.

## Consequences

**Positive:**
- **Immediate in-app response:** uploads resume seconds after reconnection while the app is open.
- **Guaranteed background completion:** verified on a device with the app killed. Android started the process for the job and the batch uploaded.

**Negative:**
- Vendor battery managers, Doze and battery saver can defer background work.
- With the app closed, retries follow WorkManager's backoff, which can grow to its 5-hour cap.
- Upload progress from the worker isolate isn't streamed to the UI, which shows an indeterminate bar for those batches.

## Alternatives considered

| Option | Why not |
|---|---|
| Periodic work only | A 15-minute minimum interval and no immediate retry |
| Foreground service | Needs a persistent notification and Android 14 foreground-service types; disproportionate for short uploads |
| A connectivity listener in the app only | Dies with the process, so it doesn't meet the background requirement |
