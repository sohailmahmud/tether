# Tether

> Stay tethered to where you work and to what you capture.

[![Android · Tether Attendance](https://github.com/sohailmahmud/tether/actions/workflows/android-attendance.yml/badge.svg)](https://github.com/sohailmahmud/tether/actions/workflows/android-attendance.yml)
[![Flutter · Tether Capture](https://github.com/sohailmahmud/tether/actions/workflows/flutter-capture.yml/badge.svg)](https://github.com/sohailmahmud/tether/actions/workflows/flutter-capture.yml)

Tether is my submission for the Intelligent Machines **Senior App Developer Technical Assessment**: two production-grade mobile apps in one repository, one per task.

Both are built to the same engineering standard:
- business rules in a framework-free domain layer
- unidirectional, lifecycle-aware state
- offline-first persistence
- every behaviour that matters covered by automated tests, CI and verification on a real device

| | App | Task | Stack |
|---|---|---|---|
| <img src="docs/icons/tether-attendance.png" width="48" alt="Tether Attendance icon"> | **Tether Attendance** — [`android-attendance/`](android-attendance) | Task 1: geo-fenced attendance. Attendance can be marked only within 50 m of a saved office location. | Native Android · Kotlin · Jetpack Compose · Kotlin Flow |
| <img src="docs/icons/tether-capture.png" width="48" alt="Tether Capture icon"> | **Tether Capture** — [`flutter-capture/`](flutter-capture) | Task 2: custom camera with batch capture and a resilient, offline-first upload engine | Flutter · BLoC/Cubit · layered architecture |

The name reflects what both apps do: attendance is tethered to a 50 m radius around the office, and captured photos stay tethered to a local queue until the server confirms them.

<p align="center">
  <img src="docs/screenshots/attendance-live-distance.gif" width="240" alt="Tether Attendance: the distance updates live as the device walks from 120 m to 7 m, switching from Out of range to In range at 50 m">
  &nbsp;
  <img src="docs/screenshots/capture-zoom-2x.jpg" width="240" alt="Tether Capture: camera at 2x zoom with the slider and 1x, 2x, 5x buttons">
  &nbsp;
  <img src="docs/screenshots/uploads-states.png" width="240" alt="Upload Manager with a batch uploading at 14%, a failed batch and an uploaded batch">
</p>

**Contents:** [Highlights](#highlights) · [Principles](#engineering-principles) · [Requirements](#requirements-traceability) · [Assumptions](#assumptions-and-interpretations) · [Structure](#project-structure) · [Approach](#architectural-approach) · [Architecture](#architecture) · [BLoC/Cubit classes](#main-bloccubit-classes) · [Decisions](#architecture-decisions) · [Persistence](#local-persistence) · [Sync](#sync-strategy) · [Errors](#error-handling) · [Mock API](#mock-api) · [Configuration](#configuration-reference) · [Dependencies](#dependencies) · [Testing](#testing-and-verification) · [AI usage](#generative-ai-usage) · [How to run](#how-to-run) · [Reviewer guide](#reviewer-guide) · [Screenshots](#screenshots) · [Release APK](#release-apk) · [Delivery](#delivery-process) · [Limitations](#known-limitations)

## Highlights

- **One geofence rule, enforced twice.** Eligibility is a single domain policy, `AttendancePolicy`, combining distance, GPS accuracy and fix freshness. The UI uses it to enable the button, and `MarkAttendanceUseCase` re-validates it at the moment of the tap, so a stale screen can never record an invalid check-in.
- **Offline-first upload engine with exactly-once processing.** A transactional SQLite queue is the system of record. Atomic claims, leases and idempotency keys keep the app and the background worker from ever uploading the same batch twice, and photos are deleted only after the server confirms them.
- **Self-healing sync with live progress.** Uploads resume without user action:
  - in the foreground, on a stable reconnection
  - in the background, through WorkManager with a network constraint and exponential backoff
  - after a crash, through lease recovery

  The Upload Manager shows each batch's progress as a percentage and bytes sent.
- **Hardware-adaptive camera.** Zoom shortcuts (0.5x, 1x, 2x, …) are derived from the device's real zoom range. Tap-to-focus is mapped through the display orientation, and camera ownership is lifecycle-safe.
- **Verified, not assumed.**
  - 222 automated tests (85 Android, 137 Flutter), from domain rules to Compose UI and end-to-end app flows.
  - Strict static analysis and CI on every pull request.
  - Signed release builds verified on a physical device, including a background upload with the app killed.

## Engineering principles

| Quality attribute | How it is achieved |
|---|---|
| **Correctness** | Each business rule lives in exactly one domain place (`AttendancePolicy`, `ProcessUploadQueue`), and decisions are re-validated at the moment they take effect |
| **Reliability** | Transactional persistence, atomic state transitions, leases for crash recovery, idempotent uploads, and bounded exponential backoff |
| **Data integrity** | Schema-level constraints (foreign keys, `CHECK`, a partial unique index); files are deleted only after the completed status is committed |
| **Responsiveness** | GPS and camera are active only while visible; hardware access is serialized; long operations report determinate progress |
| **Security and privacy** | Least-privilege permissions, cloud backup disabled, no secrets in version control, release signing outside the repository |
| **Testability** | A framework-free domain layer, explicit composition roots, and fakes only at the hardware, network and storage edges |
| **Accessibility** | Labelled controls (shutter, zoom levels, queue badge, lock state); polite live regions for status banners; upload progress exposed to assistive technology as a progress value |
| **Operability** | CI gates for formatting, lint and analysis, tests and release builds. State-transition logging is debug-only; release warnings carry error codes and exceptions, never coordinates or photo data |

## Requirements traceability

| From the brief | Implementation | Verified by |
|---|---|---|
| **Task 1:** "Set Office Location" fetches GPS coordinates and saves them locally | `SetOfficeLocationUseCase` takes a fresh high-accuracy fix (±50 m or better) and persists it in Preferences DataStore | Unit tests; device, including after a restart |
| Mark Attendance enabled only within 50 m | `AttendancePolicy.evaluate()`, re-checked by `MarkAttendanceUseCase` at the tap | Boundary tests (49.99 m in, 50.01 m out); Compose UI tests; emulator walk-in |
| Real-time distance indicator | Live fused-location updates → `StateFlow` → distance ring and "You are N m away" | Device; emulator walk-in |
| UI from the reference screenshot, in Jetpack Compose | `AttendanceScreen` | [Screenshots](#screenshots), taken at the reference's own coordinates |
| **Task 2:** custom `CameraPreviewScreen` | `CameraPreviewScreen` with `CameraCubit` | Widget tests; device |
| Pinch-to-zoom, slider and rounded buttons (0.5x, 1x, … per back camera) | Zoom levels derived at runtime from the back camera's zoom range | Unit and widget tests; device (1x, 2x, 5x on a 1x–8x camera) |
| Tap-to-focus with a visual indicator | Focus and exposure point at the tap, with an animated focus square | Device |
| Multiple batches and a "Pending Uploads" list | Persistent SQLite queue; the **Upload Manager** screen lists pending uploads with status and live progress | Real-SQL tests; app-flow tests; device, including after a restart |
| Background worker that monitors connectivity | WorkManager task with a network-connected constraint | Device: with the app killed, Android started the process for the job and the upload completed |
| Low bandwidth or no internet: images stay in the local queue | A failed upload keeps its photos and records and is retried with backoff | Tests; device (slow connection, server error, airplane mode) |
| Automatic retry once a stable connection is detected | `SyncCubit` (connection stable for 3 s) and the background worker | App-flow tests; device; emulator recording |
| Mock API with success and failure responses | `MockUploadApi` behind the `UploadApi` contract, four modes | Tests; in-app mode selector |
| **General:** BLoC/Cubit, Kotlin Flow, layered architecture, local storage, graceful permission and hardware failures | [Architecture](#architecture), [Persistence](#local-persistence), [Error handling](#error-handling) | 222 automated tests, run in CI |
| **Deliverables:** source code, README, release APK link | This repository, this README, [Release APK](#release-apk) | Both apps build from a fresh clone; the signed APKs were installed and smoke-tested on a device |

## Assumptions and interpretations

Where the brief is silent, I made deliberate, documented decisions. None of them is presented as a requirement of the assessment.

| The brief says | Interpretation | Why |
|---|---|---|
| "High accuracy" | A fix must be ±50 m or better, to check in and to set the office | A fix less certain than the 50 m geofence can't tell inside from outside ([ADR-0003](docs/adr/0003-geofence-eligibility-policy.md)) |
| "Real-time distance indicator" | Updates every 2 s while the screen is visible; a fix older than 15 s no longer counts | Live enough while walking, without running GPS in the background |
| "A stable connection is detected" | A connection that stays up for 3 s | Absorbs flapping networks without delaying recovery noticeably |
| "Background worker (e.g. workmanager) to monitor connectivity" | A one-off WorkManager task with a network-connected constraint, kept scheduled while work remains | The platform-correct way to run work when a network appears ([ADR-0006](docs/adr/0006-sync-orchestration.md)) |
| "Automatically retry" | Unlimited retries with exponential backoff (30 s doubling, capped at 15 min in-app) | Photos must never be dropped; backoff protects a failing server and the battery |
| "Mock API responses for success and failed" | A mock server with four selectable modes behind the real API contract | Every failure path can be demonstrated end to end ([ADR-0007](docs/adr/0007-api-boundary-and-mock-server.md)) |
| "Pending Uploads" list | The **Upload Manager** screen: pending, uploading, failed and recently uploaded batches, with progress | Users see what is waiting and what has already been confirmed |
| Reference UI: "Available 09:00 AM – 10:30 AM" | Not implemented | No check-in window appears in the requirements |
| Release APK link | Two APKs, one per app | The tasks are separate apps ([ADR-0001](docs/adr/0001-two-applications-one-per-task.md)) |

## Project structure

```text
tether/
├── android-attendance/          Task 1: native Android app (Kotlin, Jetpack Compose)
│   └── app/src/main/java/com/tether/attendance/
│       ├── data/
│       │   ├── local/           office location and last check-in in Preferences DataStore
│       │   └── location/        device position from the fused location provider
│       ├── domain/              models, attendance policy, repository contracts, use cases
│       ├── presentation/        Compose UI, ViewModel, theme
│       └── di/                  composition root (AppContainer)
├── flutter-capture/             Task 2: Flutter app
│   └── lib/
│       ├── main.dart            composition root
│       ├── app/                 app shell, background worker entry point, sync wiring
│       ├── core/                shared utilities
│       ├── domain/              entities, repository contracts, the upload engine (pure Dart)
│       ├── data/                upload queue (SQLite + photo files), camera, mock API,
│       │                        connectivity, WorkManager scheduling
│       └── presentation/
│           ├── camera/          CameraPreviewScreen, CameraCubit, camera widgets
│           └── uploads/         Upload Manager screen, UploadQueueCubit, SyncCubit, MockServerCubit
├── docs/
│   ├── adr/                     architecture decision records
│   ├── icons/                   app icons
│   └── screenshots/             images used in this README
└── .github/workflows/           CI for each app
```

The Android tree follows the master plan's suggested layout, with two deliberate simplifications:
- Each data source has exactly one repository, so repositories live next to their sources instead of in a separate `repository/` package.
- There is no `navigation/` package, because the app has a single screen.

## Architectural approach

Both apps apply the same architectural model, expressed in each platform's idiom.

| Concern | Tether Attendance (Android) | Tether Capture (Flutter) |
|---|---|---|
| **Style and dependency rule** | Layered: Compose → ViewModel → use cases → repositories → data sources. Dependencies point inward, and the domain has no Android imports | Layered, with ports and adapters: the domain defines contracts (`CameraRepository`, `UploadQueueRepository`, `UploadApi`, `BackgroundSyncScheduler`) that the data layer implements. The domain is pure Dart |
| **State and data flow** | Unidirectional: storage and location flows → one `StateFlow<AttendanceUiState>` → a stateless screen; intents flow back as `AttendanceActions` | Unidirectional: repositories stream into Cubits → immutable `Equatable` states → widgets; intents are Cubit method calls |
| **Concurrency** | Structured concurrency in `viewModelScope`. `flatMapLatest` and `transformLatest` cancel stale work; `conflate` drops outdated fixes; in-flight jobs guard against double taps | Two isolates (UI and WorkManager) share one native SQLite connection. Queue writes are serialized in-process, camera operations run strictly in order, and overlapping sync triggers join one run |
| **Error model** | Expected failures are typed results (`LocationResult`, `SetOfficeLocationResult`, `MarkAttendanceResult`); I/O exceptions are caught at the use-case boundary | Expected failures are typed results (`UploadResult`) or domain exceptions mapped to states (`CameraFailure`, `UploadQueueException`). Unexpected errors still produce a safe state, such as a failed attempt or a released shutter |
| **Lifecycle** | `WhileSubscribed(5_000)` + `collectAsStateWithLifecycle`: GPS runs only while the screen is visible, and survives rotation | The camera is released when the app goes inactive or another screen covers it, and is restored with its zoom; sync work outlives the UI through WorkManager |
| **Offline-first** | Office and last check-in are read from local storage; no network needed | The queue is the system of record; the UI renders persisted state, never in-memory assumptions |
| **Composition** | `AppContainer` composition root ([ADR-0008](docs/adr/0008-composition-roots-and-manual-di.md)) | `main.dart` + `SyncDependencies`, shared by the app and the worker |

## Architecture

### Tether Attendance: native Android with Kotlin Flow

```mermaid
flowchart LR
    subgraph Presentation
        Screen["AttendanceScreen<br/>(Jetpack Compose)"]
        VM["AttendanceViewModel"]
    end
    subgraph Domain
        SetOffice["SetOfficeLocationUseCase"]
        Observe["ObserveAttendanceStatusUseCase"]
        Mark["MarkAttendanceUseCase"]
        Policy["AttendancePolicy"]
    end
    subgraph Data
        Loc["FusedLocationRepository"]
        Office["DataStoreOfficeLocationRepository"]
        Att["DataStoreAttendanceRepository"]
    end
    Screen -->|user intents| VM
    VM -->|StateFlow of AttendanceUiState| Screen
    VM --> SetOffice & Observe & Mark
    SetOffice & Observe & Mark --> Policy
    SetOffice & Observe --> Loc
    SetOffice & Observe --> Office
    Mark --> Att
    VM -.->|last check-in| Att
```

- **Presentation:**
  - `AttendanceScreen` is a stateless Compose screen that renders a single `AttendanceUiState`.
  - `AttendanceViewModel` owns that state.
  - `AttendanceRoute` handles the Android-specific edges the ViewModel must not touch: runtime permissions and system settings.
- **Domain:**
  - `SetOfficeLocationUseCase` takes a fresh fix and saves it if it meets the accuracy rule.
  - `ObserveAttendanceStatusUseCase` combines the saved office with live location into an `AttendanceStatus`: not set, locating, unavailable, or measured with distance and eligibility.
  - `MarkAttendanceUseCase` re-validates eligibility and fix freshness before recording.
- **Data:** Google Play services fused location and two Preferences DataStore repositories. Each data source has exactly one repository, so no pass-through layers are added.

**State management (Kotlin Flow).**
- **Single source of truth:** `uiState` is one `StateFlow`, built by `combine`-ing the attendance status, the last check-in from storage, and a small `MutableStateFlow` of in-flight actions and errors. Storage stays authoritative, so saving an office automatically restarts tracking against it.
- **Lifecycle-scoped tracking:** the state is shared with `SharingStarted.WhileSubscribed(5_000)` and collected with `collectAsStateWithLifecycle`. GPS runs only while the screen is visible, and survives configuration changes without restarting.

**Geofence policy (`AttendancePolicy`)** ([ADR-0003](docs/adr/0003-geofence-eligibility-policy.md))

| Rule | Value | Source | Rationale |
|---|---|---|---|
| Geofence radius | 50 m, inclusive | **Assessment brief** | — |
| Distance | Haversine on a spherical Earth (under 0.3 m error at 50 m) | Design decision | Accurate at this scale without a geodesy dependency |
| Minimum accuracy | ±50 m or better, to check in **and** to set the office | **Design decision**; the brief asks for "high accuracy" without a number | A fix less certain than the geofence can't tell inside from outside, and an imprecise office would shift the whole geofence |
| Maximum fix age | 15 s; older fixes show "No GPS signal" and are refused at check-in | Design decision | Updates arrive every 2 s, so 15 s of silence means the signal is lost and the user may have moved |
| Displayed distance | Rounded **up** to whole metres | Design decision | The label always agrees with the rule: 50.0 m shows "50m" (in range), 50.2 m shows "51m" (out) |

### Tether Capture: Flutter with BLoC/Cubit

```mermaid
flowchart LR
    subgraph Presentation
        CC["CameraCubit"]
        UQC["UploadQueueCubit"]
        SC["SyncCubit"]
    end
    Worker["Background worker<br/>(WorkManager isolate)"]
    subgraph Domain
        Engine["ProcessUploadQueue"]
        CamPort["CameraRepository"]
        QueuePort["UploadQueueRepository"]
        ApiPort["UploadApi"]
        SchedPort["BackgroundSyncScheduler"]
    end
    subgraph Data
        CamRepo["PluginCameraRepository"]
        Queue["SqfliteUploadQueueRepository<br/>+ PhotoStore"]
        Api["MockUploadApi"]
        Sched["WorkmanagerSyncScheduler"]
    end
    CC --> CamPort & QueuePort
    UQC --> QueuePort
    SC --> Engine & QueuePort & SchedPort
    Worker --> Engine
    Engine --> QueuePort & ApiPort
    CamPort -.-|implemented by| CamRepo
    QueuePort -.-|implemented by| Queue
    ApiPort -.-|implemented by| Api
    SchedPort -.-|implemented by| Sched
```

- **Domain** (no Flutter or plugin imports):
  - camera capabilities, including the rule that picks the zoom buttons
  - upload queue entities and their status model
  - the `ProcessUploadQueue` engine with its `RetryPolicy` and `UploadProgress`
  - the contracts the data layer implements

  The upload engine is the only use case, because it is the only workflow that orchestrates several collaborators: the queue, the API, the clock and the retry policy. Camera and queue operations map one-to-one onto repository calls, so wrapping them in pass-through use cases would add classes without adding responsibility.
- **Data:** the `camera` and `permission_handler` plugins, the SQLite queue and photo store, the mock API, connectivity (`connectivity_plus`) and WorkManager scheduling (`workmanager`).
- **Presentation:** two screens (the camera and the Upload Manager) and four Cubits. Widgets hold no business logic. The demo-only `MockServerCubit` is left out of the diagram.
- **Composition root** (`main.dart`, `app/`):
  - Wires concrete implementations.
  - `SyncDependencies` builds the upload engine identically for the app and for the background worker isolate ([ADR-0008](docs/adr/0008-composition-roots-and-manual-di.md)).
  - The presentation layer never imports the camera plugin, so widget tests run against a stand-in preview.

**Camera behaviour.**
- **Zoom adapts to the hardware.** A 0.5x button appears only when the back camera's minimum zoom is below 1x, which is how Android exposes an ultra-wide lens. Then come 1x, 2x, 5x and 10x where the camera reaches them, and pinch and the slider cover every level in between. On Android the plugin reports every lens type as "unknown", so the zoom range is the reliable signal.
- **Tap-to-focus** maps the tap to normalised preview coordinates, which the plugin projects onto the sensor using the display orientation. Exposure is metered at the same point. Fixed-focus cameras skip it.
- **Lifecycle-safe:** the camera is released when the app goes inactive or another screen covers it, and is restored with the same zoom. The pause caused by the permission dialog itself is ignored.
- **Serialized hardware access:** open, release and capture run strictly in order, so the camera is never released mid-capture. Repeated shutter taps are ignored.
- **1080p JPEGs:** sharp enough for documentation while keeping uploads small on slow networks.

### Main BLoC/Cubit classes

| Class | Responsibility |
|---|---|
| `CameraCubit` | Owns the camera lifecycle and controls: permission, open and release, zoom, tap-to-focus, and capture into the upload queue. It exposes a sealed `CameraState`: Starting, PermissionRequired, Unavailable, Paused or Ready. |
| `UploadQueueCubit` | Streams the persistent queue to the UI (the batch being captured and the submitted batches), and submits the current batch when the user taps **Upload batch**. |
| `SyncCubit` | Decides when uploads run while the app is open: on launch, on a stable reconnection, when a retry falls due, and on user request. It exposes connectivity and per-batch upload progress, and keeps a background run scheduled while work remains. |
| `MockServerCubit` | Holds the simulated server mode, so every success and failure path can be demonstrated without a backend. |

## Architecture decisions

The significant decisions are recorded as [Architecture Decision Records](docs/adr/README.md), each with its context, consequences and the alternatives considered.

| ADR | Decision | Key trade-off |
|---|---|---|
| [0001](docs/adr/0001-two-applications-one-per-task.md) | Two independent apps, one per task | Each task uses its idiomatic stack and ships independently; reviewers install two APKs |
| [0002](docs/adr/0002-unidirectional-state-management.md) | One `StateFlow` per screen; one Cubit per concern | Deterministic, testable state; serialization is explicit instead of handled by event transformers |
| [0003](docs/adr/0003-geofence-eligibility-policy.md) | One geofence policy, re-validated at the moment of the tap | A check-in is only accepted from a fix precise enough to trust; the platform Geofencing API can't do a live 50 m check |
| [0004](docs/adr/0004-sqlite-upload-queue.md) | SQLite as the queue's system of record | ACID and multi-isolate safety, at the cost of hand-written SQL, covered by real-SQL tests; Hive, Isar and Drift were rejected |
| [0005](docs/adr/0005-exactly-once-processing.md) | Atomic claims, leases, guarded failures, idempotency keys | Effectively exactly-once storage, provided the server honours the key |
| [0006](docs/adr/0006-sync-orchestration.md) | Foreground triggers plus a constrained WorkManager task | Instant in-app response and background completion; background timing is subject to OS policy |
| [0007](docs/adr/0007-api-boundary-and-mock-server.md) | A typed `UploadApi` contract with progress; a mock server with failure modes | Every failure path can be demonstrated; a real client replaces one data-layer class |
| [0008](docs/adr/0008-composition-roots-and-manual-di.md) | Manual dependency injection through composition roots | Explicit and test-friendly; a framework would only pay off in a much larger graph |
| [0009](docs/adr/0009-security-privacy-and-release.md) | Least privilege, no cloud backup, no secrets in version control | A minimal attack surface; the keystore must be backed up outside the repository |

## Local persistence

**Tether Attendance:** Preferences DataStore, with two independent stores.
- `office_location`: latitude, longitude, fix accuracy and save time, written in a single transaction so a read never mixes old and new values. A missing, partial or out-of-range record reads as "no office set".
- `attendance`: the most recent check-in (time, distance and accuracy).

**Tether Capture:** an SQLite upload queue, the system of record until the server confirms a batch ([ADR-0004](docs/adr/0004-sqlite-upload-queue.md)).
- `upload_batches`: status, retry count, last error, next attempt time, and created, submitted and updated timestamps.
- `upload_items`: one row per photo, with its file path, size, status and capture time.

**Integrity in the schema:**
- Foreign keys from photos to batches, enabled on every connection.
- `CHECK` constraints on status values.
- A partial unique index that allows exactly one draft batch.
- Migrations run in place (schema v1 → v2 was verified on a device with a populated queue).

**Batch flow:**
- Photos go into the open *draft* batch.
- **Upload batch** turns it into a *pending* batch and the next photo starts a new draft, so any number of batches can wait in the queue.
- The draft is an addition to the master plan's four upload statuses: the batch still being captured, which is never uploaded.

**Photo files:**
- Each capture is atomically moved from the cache into app storage under `photos/<batch>/<photo>.jpg`.
- If recording it fails, the file is removed.
- Files orphaned by a process kill at an unlucky moment are swept at the next launch.

**Backup and device transfer** are disabled in both apps: a restored office location could be edited to move the geofence, and a restored queue would no longer match the server.

## Sync strategy

```mermaid
stateDiagram-v2
    [*] --> draft: first photo taken
    draft --> pending: Upload batch
    pending --> uploading: atomic claim
    failed --> uploading: retry due, reconnect or Retry now
    uploading --> completed: server confirms
    uploading --> failed: no internet, timeout or server error
    uploading --> pending: lease expired (process died)
    completed --> [*]
    note right of failed : photos and records kept, exponential backoff
    note right of completed : photos deleted only after this commit
```

`ProcessUploadQueue`, the upload engine, runs the same four steps wherever it is triggered:

1. **Recover:** a batch left *uploading* for longer than its 5-minute lease (the process died mid-upload) returns to *pending*.
2. **Claim:** the oldest due batch is marked *uploading* inside one exclusive SQLite transaction, with an update conditional on the status just read.
   - On Android, sqflite shares one native connection between the app and the background isolate and serializes their transactions.
   - The claim is therefore exactly-once across both. This was confirmed in the plugin source and covered by a concurrent-claim test.
3. **Upload** through `UploadApi`, with the batch id as the idempotency key. Bytes sent are published as `UploadProgress`, starting at 0% the moment the batch is claimed.
4. **Record the outcome:**
   - **Success:** the batch is completed, then its files are deleted.
   - **Failure:** photos and records are kept, the attempt is counted, and a retry is scheduled (30 s, doubling, capped at 15 min).
   - **No connection:** the run stops early, since every remaining batch would fail the same way.

**Guarantees, each covered by tests** ([ADR-0005](docs/adr/0005-exactly-once-processing.md)):
- **No data loss.** Files are deleted only after completion is committed.
- **No duplicate processing.** Claims are atomic, and a late failure from an attempt that outlived its lease can't overwrite a completed batch.
- **Restart safety.** Interrupted uploads are recovered by the lease.
- **Bounded retries.** Backoff limits how often a failing server is retried, and an unexpected storage error waits at least 30 s rather than spinning.

**Triggers, with no user action needed** ([ADR-0006](docs/adr/0006-sync-orchestration.md)):

| Trigger | Mechanism |
|---|---|
| App launch | Foreground run for anything left over |
| Connection returns and stays up for 3 s | `connectivity_plus` in `SyncCubit`. Failed batches retry at once, and the stability window keeps a flapping network from triggering failing attempts |
| A failed batch's retry time arrives | Foreground timer, paused while offline |
| App in the background or closed | **WorkManager** worker |

**Upload batch** and **Retry now** also start a run; they are conveniences, not the retry mechanism.

**Background worker.**
- While any batch is unfinished, one unique one-off WorkManager task is kept scheduled, with a *network connected* constraint and exponential backoff.
- WorkManager runs it in a separate isolate, even after the app is closed.
- The worker builds the same engine as the app and asks to be retried until the queue is empty.

**Cross-isolate consistency.**
- The worker's writes are announced to the app's isolate over `IsolateNameServer` (`QueueChangeChannel`), so an open Upload Manager updates the moment the background worker finishes.
- The worker never closes the shared database connection.

**Progress.** Material guidance calls for a determinate indicator whenever an operation's progress can be measured, and an upload's byte count always can.
- **Foreground uploads:** each uploading batch shows a determinate bar with its percentage and bytes sent ("14% · 64.0 KB of 444 KB"), exposed to screen readers as a progress value.
- **Background uploads:** progress lives in the worker's isolate, so those batches show an indeterminate bar.

## Error handling

**Tether Attendance:** live-tracking problems appear in the distance section, with Mark Attendance locked.

| Situation | Shown |
|---|---|
| No location permission | **Permission needed**, with **Allow location** |
| Location services off | **Location off**, with **Turn on location** |
| No fix for 15 s | **No GPS signal**, with guidance to move near a window or outdoors |
| Fix worse than ±50 m | **Weak GPS signal** with the current accuracy |

Failed user actions raise a banner that offers the fix where one exists:

| Situation | Banner |
|---|---|
| Permission denied | Explanation; asking again shows the system dialog |
| Permanently denied | Explanation with **Open settings** |
| Only approximate location granted | Precise location is required for a 50 m check, with **Open settings** |
| Location services off | **Turn on**, which opens location settings |
| No fix within 30 s while setting the office | Guidance to retry with a clearer view of the sky |
| Office fix worse than ±50 m | Not saved, with guidance to improve the signal |
| The user moved, or the fix went stale, between render and tap | Check-in refused; re-check the distance |
| Storage write fails | Retry message; previous data is kept |

When the user returns from Settings with the cause fixed, the banner clears and tracking restarts automatically. Replacing an existing office asks for confirmation, because it moves the geofence.

**Tether Capture:**

| Situation | Shown |
|---|---|
| Camera permission denied, or denied permanently | **Allow camera**, or **Open settings**. The camera opens automatically on return |
| No back camera, or the camera fails to start | A clear message, with **Try again** where retrying can help |
| A capture fails, or the photo can't be saved to the queue | A snackbar; the camera stays ready and nothing half-saved remains |
| Storage can't be opened at launch (e.g. the device is full) | A dedicated "Can't open storage" screen instead of a blank app |
| Offline | A banner in the Upload Manager: uploads resume automatically when the connection returns |
| An upload fails (no internet, timeout, server error) | "Failed once" (or "Failed N×") with the error and the next retry time. Photos stay on the device, and **Retry now** is offered |
| An upload is interrupted by the process dying | The batch returns to the queue with a note, and is retried |

Only the camera permission is requested. Permissions that plugins declare but the app doesn't use are removed from the merged manifest: the camera plugin's microphone and storage permissions, and the workmanager plugin's notification permission.

## Mock API

The brief provides no backend. `MockUploadApi` implements the `UploadApi` contract in the data layer, so replacing it with a real HTTP client changes nothing above that layer ([ADR-0007](docs/adr/0007-api-boundary-and-mock-server.md)).

- **Real connectivity:** with no network (e.g. airplane mode) every upload fails with "No internet connection", whatever the mode.
- **Progress:** bytes sent are reported every 100 ms. A timeout or a dropped connection stops at the fraction actually transferred.
- **Idempotent:** re-sending a stored batch returns its original receipt, which is the contract a real server must honour for the batch-id key.
- **Modes**, selected under **Mock server** in the Upload Manager and shared with the background worker through a small settings file:

| Mode | Behaviour |
|---|---|
| Normal | Succeeds after a transfer time based on batch size (about 2 MB/s, at least 0.5 s) |
| Slow connection | About 16 KB/s, so a typical photo batch times out after 8 s |
| Server error | Fails with 503 Service Unavailable |
| Unstable connection | About half of the uploads drop part-way |

## Configuration reference

Behavioural constants live next to the rule they parameterise, never in UI code.

| Setting | Value | Defined in |
|---|---|---|
| Geofence radius | 50 m | `AttendancePolicy.RADIUS_METERS` |
| Minimum fix accuracy | ±50 m | `AttendancePolicy.MAX_ACCURACY_METERS` |
| Maximum fix age | 15 s | `AttendancePolicy.MAX_FIX_AGE_MILLIS` |
| Location update interval (fastest) | 2 s (1 s) | `FusedLocationRepository` |
| Office fix timeout | 30 s | `FusedLocationRepository` |
| UI state keep-alive after the screen leaves | 5 s | `AttendanceViewModel` (`WhileSubscribed`) |
| Retry backoff | 30 s, doubling, capped at 15 min | `RetryPolicy` |
| Upload lease (crash recovery) | 5 min | `RetryPolicy.uploadLease` |
| Stable-connection window | 3 s | `SyncCubit.stableConnectionDelay` |
| Pause after an unexpected storage error | 30 s | `SyncCubit.errorRetryDelay` |
| Background worker backoff | Exponential from 30 s | `WorkmanagerSyncScheduler` |
| Mock request timeout | 8 s | `MockUploadApi.timeout` |
| Mock bandwidth (normal / slow) | About 2 MB/s / 16 KB/s | `MockUploadApi` |
| Progress reporting interval (mock) | 100 ms | `MockUploadApi.progressInterval` |
| Photo resolution | 1080p JPEG | `PluginCameraRepository` |
| SQLite busy timeout | 5 s | `UploadQueueDatabase` |

## Dependencies

Dependencies are stable, widely adopted and kept to what each app needs. Versions are pinned through the Gradle version catalog and `pubspec.lock`.

**Tether Attendance**

| Library | Purpose | Why |
|---|---|---|
| Play services location (`FusedLocationProviderClient`) | Fixes with accuracy and time | Best accuracy and battery behaviour on Android; required by the master plan |
| Preferences DataStore | Office and last check-in | Asynchronous, transactional, Flow-native; replaces SharedPreferences |
| `kotlinx-coroutines-play-services` | `await()` on Play services tasks, with cancellation | Location requests are cancelled when the screen closes |
| Lifecycle (`runtime-compose`, `viewmodel-compose`) | `collectAsStateWithLifecycle`, ViewModel | Lifecycle-aware collection |
| *Test:* Robolectric, Compose UI test, `kotlinx-coroutines-test` | JVM UI tests and virtual time | Compose UI tests run in CI without an emulator |

**Tether Capture**

| Library | Purpose | Why |
|---|---|---|
| `flutter_bloc`, `equatable` | Cubits and value-equal states | Required by the brief; Equatable makes state changes testable |
| `camera` | Preview, zoom, focus, capture | First-party plugin (CameraX on Android) |
| `permission_handler` | Camera permission, including "permanently denied" | The camera plugin can't tell denied from permanently denied |
| `sqflite`, `path`, `path_provider` | The upload queue and photo storage | Transactions and multi-isolate safety ([ADR-0004](docs/adr/0004-sqlite-upload-queue.md)) |
| `workmanager` | Background worker | WorkManager is Android's supported scheduler for deferrable, constrained work |
| `connectivity_plus` | Connectivity changes in the foreground | Drives the stable-reconnection trigger |
| *Test:* `bloc_test`, `fake_async`, `sqflite_common_ffi` | Cubit sequences, virtual time, real SQL on the host | Deterministic tests for timing and storage |

## Testing and verification

**Automated tests: 222.**

| App | Layer | Tests | What they prove |
|---|---|---|---|
| Android | Domain | 33 | Geofence boundary, accuracy and freshness rules, distance maths, use-case outcomes |
| Android | Persistence | 14 | Record encoding, and the DataStore repositories on real files: restart survival, and corrupt or partial data reads as "not set" |
| Android | Presentation | 26 | ViewModel state transitions: permissions, errors, double taps, stale fixes, lifecycle |
| Android | Compose UI | 12 | `AttendanceScreen` on the JVM through Robolectric: each state's text, button enablement, the replace-office confirmation, and every action a tap reports |
| Flutter | Domain | 18 | Upload engine outcomes and progress, retry policy, zoom-level selection |
| Flutter | Data | 38 | Real SQL through `sqflite_common_ffi`, including concurrent claims, restart survival, schema upgrade and orphan cleanup, plus every mock API mode and its progress |
| Flutter | BLoC/Cubit | 42 | Camera lifecycle, capture concurrency, sync triggers and timing, upload progress, queue streaming |
| Flutter | Widgets and app wiring | 34 | Screens (including determinate and indeterminate progress), the background run result, cross-isolate notifications, the startup failure screen |
| Flutter | App flows | 5 | The real `TetherCaptureApp` end to end, with fakes only for the camera and network: capture → upload → uploaded; offline → queued → automatic upload once the connection is stable; server error → automatic retry after backoff; Retry now; separate batches |

**Master plan test matrices.** Every scenario in the plan's Android and Flutter test matrices, with how it was verified. A dash means the scenario was not verified that way.

<details>
<summary><b>Android test matrix</b> (16 scenarios)</summary>

| Scenario | Automated | Device or emulator |
|---|---|---|
| Permission granted | ViewModel tests | ✓ Device |
| Permission denied / permanently denied | ViewModel and Compose UI tests | ✓ Device |
| GPS disabled | ViewModel and Compose UI tests | ✓ Emulator |
| Location unavailable (no fix) | Use-case and Compose UI tests | ✓ Device |
| Office location not configured | Compose UI test | ✓ Emulator |
| Office location configured | Use-case and DataStore tests | ✓ Device and emulator |
| User outside 50 m | Policy and Compose UI tests | ✓ Emulator (120 m) |
| User near the boundary | Boundary tests (49.99 m / 50.01 m) | ✓ Device (50 m / 51 m) |
| User inside 50 m | Policy, use-case and Compose UI tests | ✓ Device and emulator |
| Poor location accuracy | Policy, use-case and Compose UI tests | ✓ Device (±70 m) |
| App backgrounded | ViewModel test (tracking stops after 5 s) | ✓ Device (location requests stopped) |
| App resumed | ViewModel tests | ✓ Device |
| App restarted | DataStore restart tests | ✓ Device |
| Saved office location persists | DataStore tests | ✓ Device |
| Real-time distance updates | ViewModel test | ✓ Device and emulator |
| Attendance blocked outside the allowed range | Use-case and Compose UI tests | ✓ Emulator |

</details>

<details>
<summary><b>Flutter test matrix</b> (21 scenarios)</summary>

| Scenario | Automated | Device or emulator |
|---|---|---|
| Camera permission denied | Cubit and widget tests | ✓ Device |
| Camera permission granted | Cubit tests | ✓ Device |
| Camera initialization failure | Cubit and widget tests | — |
| Zoom buttons | Widget tests | ✓ Device |
| Zoom slider | Widget test | — |
| Pinch zoom | Widget test | — |
| Tap focus | Cubit and widget tests | ✓ Device |
| Focus indicator | Widget test | ✓ Device |
| Capture image | Cubit, repository and app-flow tests | ✓ Device |
| Multiple images | Repository and app-flow tests | ✓ Device |
| Multiple batches | Repository and app-flow tests | ✓ Device and emulator |
| Pending uploads | Widget and app-flow tests | ✓ Device and emulator |
| API success | Engine, mock API and app-flow tests | ✓ Device |
| API failure | Engine, mock API and app-flow tests | ✓ Device (server error) |
| No internet | Engine, Cubit and app-flow tests | ✓ Device (airplane mode) |
| Low or unstable connectivity | Mock API tests (both modes) | ✓ Device (slow connection) |
| Internet restored | Cubit and app-flow tests | ✓ Device and emulator |
| App restarted with pending uploads | Repository restart and Cubit launch tests | ✓ Device |
| Background retry | Background-run tests | ✓ Device (WorkManager `RETRY` → `SUCCESS`, app killed) |
| Multiple pending batches | Engine and repository tests | ✓ Device |
| Duplicate-processing protection | Concurrent-claim test (mutation-checked) | ✓ Device (app and worker overlapping) |

</details>

**Techniques:**
- **Virtual time** (`fake_async`) for retry timers and connection-stability windows.
- **`bloc_test`** for state sequences.
- **Mutation checks** on critical guarantees. Each one disables the code under test and confirms the suite fails:

  | Code disabled | Result |
  |---|---|
  | Atomic claim | The concurrency test fails with 12 claims for 6 batches |
  | Late-failure guard | A completed batch regresses to failed |
  | Locked Mark Attendance button | Five UI tests fail |
  | Reconnect retry | The offline flow test fails |
- **Coverage:** Tether Capture's suite covers 94% of lines (`flutter test --coverage`).

**Continuous integration** (GitHub Actions). Each app has its own workflow, triggered by changes to that app on pushes to `main` and on pull requests:

| Workflow | Steps |
|---|---|
| [Android · Tether Attendance](.github/workflows/android-attendance.yml) | <ol><li>ktlint</li><li>Android Lint</li><li>unit and Compose UI tests</li><li>debug and R8 release builds</li></ol>Test reports and the debug APK are uploaded as artifacts. |
| [Flutter · Tether Capture](.github/workflows/flutter-capture.yml) | <ol><li>formatting</li><li>`flutter analyze`</li><li>all tests with coverage</li><li>a release APK build</li></ol>The coverage summary and the APK are uploaded. |

CI has no signing secrets, so its release builds fall back to the debug key. Signed APKs are built locally (see [How to run](#how-to-run)).

**Static analysis:**
- **Android:** ktlint and Android Lint, with 0 issues.
- **Flutter:** strict analyzer settings (`strict-casts`, `strict-inference`, `strict-raw-types`), and unawaited futures are errors.

**Device verification:** Samsung Galaxy A04s, Android 14. Evidence came from screenshots, logcat, and Android's JobScheduler and location dumps.

| Scenario | Result |
|---|---|
| Geofence at the boundary | With an office 50 m away, GPS jitter switched the screen between "50 m, In range" and "51 m, Out of range" |
| Location lifecycle | Location requests stopped within seconds of leaving the app and resumed on return |
| Restart persistence | The office location and the upload queue survived force-stop and relaunch; the queue also survived an in-place schema upgrade |
| Background upload, app killed (release build) | When the backoff ended, Android started the process for the WorkManager job, and the worker uploaded the batch with no UI |
| Offline → online | A batch failed in airplane mode and uploaded about 11 s after reconnecting, with no tap |
| Low bandwidth | Progress climbed at about 16 KB/s, the batch timed out with its photos kept, and it uploaded automatically afterwards |
| App and worker concurrently | Overlapping runs never processed the same batch twice |
| Final signed APKs, fresh install | Permission prompts appeared on first launch. The office was saved from a ±34 m fix and a check-in was recorded. A ±70 m fix locked check-in until accuracy recovered. A 3-photo batch was captured and uploaded |

## Generative AI usage

I used generative AI as an engineering accelerator in two distinct roles, while keeping ownership of requirements, architecture and verification.

| Stage | Tool | Role |
|---|---|---|
| Planning | **ChatGPT** | Turned the assessment PDF into a master execution plan for a senior mobile engineer. It defines: <ul><li>the role and priorities</li><li>the PDF as the single source of truth</li><li>ten time-boxed phases with milestone gates</li><li>a requirements traceability matrix with an ID and verification method for every requirement</li><li>platform architecture guidance</li><li>test matrices, a quality bar and git discipline</li><li>a standard report for every phase</li></ul> |
| Execution | **Claude Code** | Executed the plan phase by phase in this repository: <ul><li>inspected the code and implemented the phase on a feature branch</li><li>ran formatting, static analysis and tests</li><li>deployed builds to a physical device over adb and collected evidence</li><li>reported each phase against the traceability matrix</li></ul> |

**Engineering workflow:**
1. **Plan:** the master prompt fixed scope, priorities and acceptance criteria before any code was written.
2. **Execute:** each phase was implemented in isolation, then stopped for review with a report of what changed, evidence, requirement status and a proposed commit.
3. **Review and decide:** I reviewed every phase before it was committed and merged through a pull request. I made the architectural and delivery decisions (recorded as [ADRs](docs/adr/README.md)):
   - the storage engine for the queue
   - the branching strategy
   - release packaging
   - keeping real location data out of published screenshots
4. **Verify:** AI output was treated as a proposal until proven:
   - by automated tests and mutation checks
   - by reading library source before relying on undocumented behaviour (sqflite's shared connection between isolates)
   - by device evidence

**Where verification changed the outcome:**
- **Cross-isolate state:** device testing showed that a batch uploaded by the background worker still appeared as failed on an open screen. Fixed with an `IsolateNameServer` change channel.
- **Indoor GPS:** transient "location unavailable" callbacks produced false "No GPS signal" states. Replaced with freshness-based detection, where a fix older than 15 s counts as lost.
- **Hardening review:**
  - A late failure could revert a completed batch.
  - A persistent storage fault could cause a busy retry loop.
  - An imprecise fix could be saved as the office.

  All three were fixed with regression tests.

### Essential prompts

**1. Master execution prompt** (prepared with ChatGPT and used as the standing instruction set in Claude Code). Representative excerpts, verbatim:

> You are my senior software engineering assistant for the Intelligent Machines Ltd. Senior App Developer Technical Assessment. […] Your role is to help me design, implement, review, debug, test, and document each phase while keeping the project technically consistent from beginning to end.

> Treat the provided Intelligent Machines assessment PDF as the authoritative source for explicit requirements. Do not silently invent additional mandatory requirements.

> Work on ONE phase at a time. […] Run relevant formatting, static analysis, tests, and build checks. Review for regressions. Update requirement statuses based only on actual verification.

> Prevent: duplicate worker processing, conflicting state transitions, deletion before success, duplicate retry processing. Prefer idempotent processing behavior.

> Do not mark a requirement as DONE merely because code exists.

**2. Phase execution prompts.** Because the master prompt defined each phase's scope, checks and report format, each phase was started with a one-line instruction such as `start Phase 6`. After review, the next one began with `commit, merge and start Phase 7`.

**3. Architecture and verification requests** (summarised):
- Evaluate SQLite against Hive and other options (Isar, Drift) for a queue shared with a background isolate. *Outcome:* SQLite, for transactions and multi-isolate safety.
- Recommend an enterprise branching strategy and repository visibility. *Outcome:* a feature branch and pull request per phase, with the repository kept private until submission.
- Re-run background synchronization on the physical device after a manual airplane-mode test. *Outcome:* the cross-isolate stale-state defect was found and fixed.

## How to run

**Prerequisites:**
- JDK 17+, Android SDK 37 and Flutter 3.44.x (stable).
- The Android SDK location, either in `ANDROID_HOME` or in a `local.properties` that Android Studio writes the first time it opens the project.
- An Android device or emulator. A physical device is recommended for GPS and camera.

```bash
git clone https://github.com/sohailmahmud/tether.git
cd tether
```

**Tether Attendance:**

```bash
cd android-attendance
./gradlew installDebug
```

Alternatively, open `android-attendance/` in Android Studio and run the `app` configuration.

**Tether Capture:**

```bash
cd flutter-capture
flutter pub get
flutter run
```

**Trying it out:**

- **Attendance:**
  - Tap **Set Office Location** and allow precise location; the ring shows 0 m.
  - Move more than 50 m away and Mark Attendance locks.
  - On an emulator, simulate movement instead (longitude first):

    ```bash
    adb emu geo fix -74.0060 40.7128     # set the office here
    adb emu geo fix -74.0060 40.7138791  # about 120 m north: Out of range
    ```

- **Capture:**
  - Take a few photos and tap **Upload batch**.
  - In the **Upload Manager**, use **Mock server** to switch between Normal, Slow connection, Server error and Unstable connection.
  - To see automatic recovery, enable airplane mode, upload a batch, then disable it.
    - With the app open, the batch uploads a few seconds later.
    - With the app closed, the background worker uploads it once the network is back and its backoff has passed.

**Release builds:**

```bash
cd android-attendance && ./gradlew assembleRelease    # app/build/outputs/apk/release/
cd flutter-capture && flutter build apk --release     # build/app/outputs/flutter-apk/
```

Release signing reads `android-attendance/keystore.properties` and `flutter-capture/android/key.properties`. Both are git-ignored; see the `.example` files next to them. Without them, release builds are signed with the debug key, so a fresh clone still produces installable APKs.

**Quality checks:**

```bash
# Android: formatting, lint, unit and Compose UI tests (85)
cd android-attendance && ./gradlew ktlintCheck lintDebug testDebugUnitTest

# Flutter: formatting, static analysis, unit, widget and app-flow tests (137)
cd flutter-capture && dart format --set-exit-if-changed lib test && flutter analyze && flutter test
```

**Toolchain:**

| | Version |
|---|---|
| Flutter / Dart | 3.44.6 (stable) / 3.12.2 |
| Android Gradle Plugin | 9.1.1 (built-in Kotlin) |
| Kotlin | 2.3.20 |
| Gradle | 9.3.1 (wrapper, checksum-pinned) |
| compileSdk / targetSdk | 37 / 36 |
| minSdk | 26 (Android) · 24 (Flutter) |
| JDK | 17 or newer |

## Reviewer guide

### Triggering each scenario

| Scenario | How to trigger it | Expected result |
|---|---|---|
| Location permission denied | Deny the prompt after **Set Office Location**; deny again for "don't ask again" | A banner; the second time with **Open settings**. Returning with permission granted restarts tracking |
| Approximate location only | Choose **Approximate** in the prompt | A banner explaining that precise location is required, with **Open settings** |
| Location services off | Turn location off in quick settings | **Location off** with **Turn on location**; check-in locked |
| Outside 50 m | Move away, or use `adb emu geo fix` on an emulator | **Out of range** with the distance; check-in locked |
| Weak signal | Stay deep indoors, away from windows | **Weak GPS signal** with the current accuracy; check-in locked |
| Camera permission denied | Deny the camera prompt (twice for "don't ask again") | **Allow camera**, then **Open settings**; the camera opens on return |
| No internet | Airplane mode on, then **Upload batch** | "Failed once · No internet connection", the offline banner, photos kept. Airplane mode off: the batch uploads by itself within seconds |
| Low bandwidth | **Mock server → Slow connection**, then upload | Progress climbs at about 16 KB/s, times out after 8 s, photos kept, retried with backoff |
| Server error | **Mock server → Server error** | "Server error (503)", the next retry time, and **Retry now** |
| Unstable connection | **Mock server → Unstable connection** | About half of the uploads drop part-way and are retried |
| Background completion | Make a batch fail, switch the mock back to **Normal**, then close the app | WorkManager uploads it once its backoff passes; reopening shows **Uploaded** |
| Restart with pending uploads | Airplane mode on, upload, force-stop, airplane mode off, reopen | The batch uploads on launch |

### Inspecting local state

On debug builds (`./gradlew installDebug`, `flutter run`); release builds are not debuggable. Force-stop the app first so the copies are consistent.

```bash
# Tether Attendance: DataStore files (protobuf)
adb shell run-as com.tether.attendance ls files/datastore
adb exec-out run-as com.tether.attendance cat files/datastore/office_location.preferences_pb > office_location.preferences_pb
protoc --decode_raw < office_location.preferences_pb

# Tether Capture: the upload queue, photo files and the mock server mode
adb exec-out run-as com.tether.capture cat databases/upload_queue.db > upload_queue.db
sqlite3 upload_queue.db "SELECT id, status, retry_count, last_error FROM upload_batches;"
adb shell run-as com.tether.capture ls -R app_flutter/photos
adb shell run-as com.tether.capture cat app_flutter/mock_server_mode.txt
```

## Screenshots

**Sources:**
- **Attendance screens:** an emulator with a simulated location, placed at the reference screenshot's coordinates.
- **Upload Manager screens:** the emulator's virtual camera scene.
- **Zoom and focus:** a physical device, because the emulator camera supports neither.

**Tether Attendance**

| Office not set | 120 m away, out of range | In range, attendance marked |
|---|---|---|
| <img src="docs/screenshots/attendance-office-not-set.png" width="240" alt="Office location not set yet"> | <img src="docs/screenshots/attendance-out-of-range.png" width="240" alt="120 m away, out of range, Mark Attendance locked"> | <img src="docs/screenshots/attendance-marked.png" width="240" alt="6 m away, in range, last marked today"> |

| Live distance (walking in from 120 m) | Dark theme | Location services off |
|---|---|---|
| <img src="docs/screenshots/attendance-live-distance.gif" width="240" alt="Distance counting down from 120 m to 7 m, switching to In range at 50 m"> | <img src="docs/screenshots/attendance-dark.png" width="240" alt="Dark theme, in range"> | <img src="docs/screenshots/attendance-location-off.png" width="240" alt="Location off, with a Turn on location button"> |

**Tether Capture**

| Hardware zoom (1x–8x camera) | Tap-to-focus | Batch being captured |
|---|---|---|
| <img src="docs/screenshots/capture-zoom-2x.jpg" width="240" alt="2x zoom selected, slider moved"> | <img src="docs/screenshots/capture-tap-to-focus.jpg" width="240" alt="Yellow focus square at the tapped point"> | <img src="docs/screenshots/capture-batch.jpg" width="240" alt="Three photos in the batch, Upload batch (3)"> |

| Upload Manager: progress, failure, success | Low bandwidth: progress, then timeout | Offline |
|---|---|---|
| <img src="docs/screenshots/uploads-states.png" width="240" alt="Upload Manager with a batch uploading at 14%, a failed batch and an uploaded batch"> | <img src="docs/screenshots/uploads-slow-progress.gif" width="240" alt="Progress climbing from 5% to 27% at about 16 KB/s, then the batch fails with a timeout and keeps its photos"> | <img src="docs/screenshots/uploads-offline.png" width="240" alt="Offline banner; failed batches keep their photos"> |

| Reconnected: recovers by itself | Mock server modes |
|---|---|
| <img src="docs/screenshots/uploads-auto-retry.gif" width="240" alt="After airplane mode is turned off, the failed batches upload with live progress and no tap"> | <img src="docs/screenshots/uploads-mock-server.png" width="240" alt="Mock server sheet: Normal, Slow connection, Server error, Unstable connection"> |

## Release APK

| App | Download | Size | Runs on |
|---|---|---|---|
| Tether Attendance 1.0.0 | [tether-attendance-v1.0.0.apk](https://github.com/sohailmahmud/tether/releases/download/v1.0.0/tether-attendance-v1.0.0.apk) | 1.4 MB | Android 8.0+ (API 26) with Google Play services |
| Tether Capture 1.0.0 | [tether-capture-v1.0.0.apk](https://github.com/sohailmahmud/tether/releases/download/v1.0.0/tether-capture-v1.0.0.apk) | 50 MB | Android 7.0+ (API 24) |

The [v1.0.0 release page](https://github.com/sohailmahmud/tether/releases/tag/v1.0.0) has both APKs and their SHA-256 checksums.

- **Signing:** both APKs are signed with the same release certificate (`CN=Sohail Mahmud, O=Tether`, SHA-256 `ee206ca23f0d2de83af4d4c9dfba2c5b96f4f2c612c716935e1395893247187f`).
- **Build:**
  - Tether Attendance is R8-shrunk.
  - Tether Capture is a universal APK (arm64-v8a, armeabi-v7a, x86_64) so it installs on any device, which accounts for its size.
- **Install:** open the APK on the device and allow installs from that source when Android asks.

**Packaging decision.** The two tasks are delivered as two apps, so there are two APKs. Combining them would mean embedding Flutter in the native app: integration the brief doesn't ask for, and risk that adds nothing to either task.

## Delivery process

The work followed the master plan's ten phases. Each phase was built on its own branch, verified (formatting, analysis, tests and device checks), reported against the traceability matrix, and merged through a pull request with a [Conventional Commits](https://www.conventionalcommits.org/) message.

| Phase | Scope | Pull request |
|---|---|---|
| 1 | Project foundation: both apps, toolchain, quality gates | Initial commit |
| 2 | Android: office location, permissions, persistence | [#1](https://github.com/sohailmahmud/tether/pull/1) |
| 3 | Android: 50 m validation, live distance, failure states | [#2](https://github.com/sohailmahmud/tether/pull/2) |
| 4 | Flutter: custom camera, zoom, focus, lifecycle | [#3](https://github.com/sohailmahmud/tether/pull/3) |
| 5 | Flutter: batch capture and the persistent queue | [#4](https://github.com/sohailmahmud/tether/pull/4) |
| 6 | Flutter: resilient upload engine and mock API | [#5](https://github.com/sohailmahmud/tether/pull/5) |
| 7 | Flutter: background sync and automatic retry | [#6](https://github.com/sohailmahmud/tether/pull/6) |
| 8 | Hardening review across both apps | [#7](https://github.com/sohailmahmud/tether/pull/7) |
| 9 | Documentation and screenshots | [#8](https://github.com/sohailmahmud/tether/pull/8) |
| 10 | Release build, CI, expanded tests, upload progress, app icon, ADRs | [#9](https://github.com/sohailmahmud/tether/pull/9) |

Release notes are in the [changelog](CHANGELOG.md).

## Known limitations

**Tether Attendance**

- **Deviations from the reference UI:**
  - The map is a drawn placeholder, since a map SDK needs an API key the brief doesn't provide.
  - The "Available 09:00 AM – 10:30 AM" check-in window is not implemented, because the brief doesn't require it.
  - There is no back arrow, since this is the app's only screen.
- **Not covered:** mock (spoofed) locations aren't detected, and any user can set the office. In production that would be an administrator action, enforced on a server.
- **Local only:** only the most recent check-in is stored, with no history or server sync.

**Tether Capture**

- **Connectivity:** "online" means a network connection, not proven internet reachability. Behind a captive portal, uploads fail and back off until the network really works.
- **Background execution:** Android may defer background work (Doze, battery saver, vendor battery managers). While the app is closed, retries follow WorkManager's backoff, which can grow to its 5-hour cap if the server keeps failing; with the app open they are capped at 15 minutes.
- **Progress from the worker:** uploads run by the background worker show an indeterminate bar, because their progress lives in another isolate.
- **Mock server state:** the mock keeps its idempotency record in memory, separately in each isolate, and loses it on restart. A real server persists it.
- **Camera scope:** portrait only, with no flash or front camera (the brief asks for back-camera zoom and focus). An ultra-wide lens that Android exposes only as a separate camera, rather than through zoom below 1x, gets no 0.5x button.
- **Batch editing:** individual photos can't be removed from a batch before upload.
