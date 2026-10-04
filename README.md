# Tether

> Stay tethered to where you work and to what you capture.

Tether is a two-app submission for the Intelligent Machines **Senior App Developer Technical Assessment**:

| App | Task | Stack |
|---|---|---|
| **Tether Attendance** — [`android-attendance/`](android-attendance) | Task 1: geo-fenced attendance. Mark attendance only within 50 m of a saved office location. | Native Android · Kotlin · Jetpack Compose · Kotlin Flow |
| **Tether Capture** — [`flutter-capture/`](flutter-capture) | Task 2: custom camera with batch capture and a resilient, offline-first upload queue | Flutter · BLoC/Cubit · layered architecture |

The name comes from what both apps do. Attendance is tethered to a 50 m radius around the office. Captured photos stay tethered to a local queue until the server confirms they were uploaded.

> **Status:** in development. This README is completed as each feature lands. It only describes what is implemented.

---

## Project structure

```text
tether/
├── android-attendance/          Task 1: native Android app
│   └── app/src/main/java/com/tether/attendance/
│       ├── data/
│       │   ├── local/           office location in Preferences DataStore
│       │   └── location/        device position from the fused location provider
│       ├── domain/              models, repository contracts, use cases
│       ├── presentation/        Compose UI, ViewModels, theme
│       └── di/                  manual dependency wiring
└── flutter-capture/             Task 2: Flutter app
    └── lib/
        ├── app/                 app shell, composition root, BLoC observer
        ├── core/                shared utilities
        ├── domain/              entities, repository contracts
        ├── data/                data sources, repository implementations
        └── presentation/        screens, widgets, BLoCs/Cubits
```

## Architecture

### Tether Attendance (Android)

The app has three layers: **presentation → domain → data**.

- **Presentation:** `AttendanceScreen` is a stateless Compose screen that renders one `AttendanceUiState`. `AttendanceViewModel` exposes that state as a `StateFlow`. `AttendanceRoute` connects the two and handles the Android parts the ViewModel must not touch: the permission dialog and the system settings screens.
- **Domain:** models, repository interfaces, the attendance rules, and three use cases:
  - `SetOfficeLocationUseCase` takes a fresh fix and saves it as the office.
  - `ObserveAttendanceStatusUseCase` combines the saved office with live location into an `AttendanceStatus`: office not set, locating, unavailable, or measured with a distance and eligibility.
  - `MarkAttendanceUseCase` re-checks the rules at the moment of the tap, then records the check-in.
- **Data:** `FusedLocationRepository` (Google Play services location), `DataStoreOfficeLocationRepository` and `DataStoreAttendanceRepository`. Each data source has exactly one repository, so the repository lives next to its source instead of in a separate pass-through layer.

#### State management (Kotlin Flow)

`AttendanceViewModel.uiState` is a `StateFlow` built by `combine`-ing three flows: the attendance status, the last check-in from DataStore, and a small `MutableStateFlow` holding in-progress actions and errors. Nothing on screen is copied by hand, so storage stays the single source of truth: a saved office reaches the screen through its flow and restarts tracking against the new office.

The state is shared with `SharingStarted.WhileSubscribed(5_000)` and collected with `collectAsStateWithLifecycle`. Location updates therefore run only while the screen is visible, and stop five seconds after it leaves, which is long enough to survive a rotation without restarting GPS. On the test phone, the platform's location requests for the app switched OFF within seconds of pressing Home and resumed on return.

#### Attendance rules (`AttendancePolicy`)

One function, `AttendancePolicy.evaluate()`, decides eligibility. The screen and `MarkAttendanceUseCase` both call it rather than comparing distances themselves.

| Rule | Value | Source |
|---|---|---|
| Geofence radius | 50 m, inclusive | Assessment brief |
| Distance | Haversine on a spherical Earth; under 0.3 m error at 50 m | Implementation choice |
| Minimum accuracy | Fix must be ±50 m or better | **My decision.** The brief asks for "high accuracy" without a number; a fix less certain than the geofence can't tell inside from outside |
| Maximum fix age | 15 s; older fixes show "No GPS signal" and are refused at check-in | **My decision.** Updates arrive every 2 s, so 15 s without one means the signal is lost |

Distances on screen are rounded **up** to whole metres, so the label always agrees with the rule: 50.0 m shows "50m" and is in range, while 50.2 m shows "51m" and is out. On the test phone, an office placed 50 m away switched between "50 m, In range" and "51 m, Out of range" as GPS jitter crossed the line.

Dependencies are wired by hand in `AppContainer`, because one screen and three repositories don't justify a DI framework.

### Tether Capture (Flutter)

Layered architecture with BLoC/Cubit state management: **presentation (widgets + BLoC/Cubit) → domain → data**.

- **Domain** (pure Dart, no Flutter or plugin imports):
  - Camera: `CameraCapabilities` (the zoom range and focus support read from the device at runtime, plus the rule that picks the zoom shortcut buttons), `CapturedPhoto`, `CameraFailure`, and the `CameraRepository` interface.
  - Upload queue: `UploadBatch`, `UploadItem`, `UploadStatus`, `UploadQueueSnapshot`, and the `UploadQueueRepository` interface.
- **Data:**
  - `PluginCameraRepository` (the `camera` and `permission_handler` plugins).
  - `SqfliteUploadQueueRepository`, backed by `UploadQueueDatabase` (SQLite schema) and `PhotoStore` (photo files).
- **Presentation:**
  - Camera: `CameraCubit` and `CameraPreviewScreen`, with small widgets for the zoom controls, focus indicator, shutter and thumbnail.
  - Uploads: `UploadQueueCubit` and `PendingUploadsScreen`.
- **Composition root** (`main.dart`, `app/`): creates the concrete repository and hands the screen a preview builder. The presentation layer never imports the camera plugin, and widget tests use a stand-in preview.

#### Camera behaviour

- **Zoom shortcuts come from the hardware.** A 0.5x button appears only when the back camera's minimum zoom is below 1x, which is how Android exposes an ultra-wide lens. On Android the camera plugin reports every lens type as "unknown", so the zoom range is the reliable signal. After that come 1x and then 2x, 5x and 10x where the camera reaches them. The vertical slider and pinch cover every level in between. The test phone (Galaxy A04s, 1x–8x, no ultra-wide) shows 1x, 2x and 5x.
- **Tap-to-focus** converts the tap to 0–1 preview coordinates, which the camera plugin maps to the sensor taking display orientation into account. Exposure is metered at the same point, and an animated square marks the spot. Fixed-focus cameras skip it.
- **Lifecycle:** following the camera plugin's guidance, the camera is released when the app goes inactive and reopened on resume, keeping the zoom level. The pause and resume caused by the permission dialog itself are ignored, so the camera isn't torn down while the user answers it.
- **Concurrency:** opening, releasing and capturing run one at a time in call order, so the camera can never be released mid-capture. A second shutter tap during a capture is ignored.
- **Photos** are 1080p JPEGs (`ResolutionPreset.veryHigh`), sharp enough for documentation while keeping uploads small.

### Main BLoC/Cubit classes

| Class | Responsibility |
|---|---|
| `CameraCubit` | Owns the camera screen: permission, opening and releasing the camera (with the app lifecycle and while another screen covers it), zoom (buttons, slider, pinch), tap-to-focus, and capture straight into the upload queue. Its sealed `CameraState` is Starting, PermissionRequired, Unavailable, Paused or Ready. |
| `UploadQueueCubit` | Follows the persistent upload queue (the batch being captured and the submitted batches) for the camera badge and the Pending Uploads screen, and submits the batch being captured when the user taps **Upload batch**. |
| `SyncCubit` | Runs the upload engine (`ProcessUploadQueue`) when an upload should start (app launch, a submitted batch, **Retry now**) and shows when a run is in progress. Per-batch progress comes from the queue itself. |
| `MockServerCubit` | Holds the mock server mode chosen on Pending Uploads, so reviewers can trigger each failure path. |

## Local persistence

**Tether Attendance** uses Preferences DataStore, with two files that change independently:

- `office_location`: latitude, longitude, fix accuracy and save time, written in one transaction so a read never mixes old and new values. A missing, partial or out-of-range record reads as "no office set".
- `attendance`: the most recent check-in (time, distance from the office, fix accuracy), shown under the Mark Attendance button.

Both survive app restarts. Backup and device-to-device transfer are disabled for the app's data, so the geofence can't be moved by editing a backup.

**Tether Capture** keeps its upload queue in SQLite (`sqflite`):

- `upload_batches`: id, status, retry count, last error, created, submitted and updated times.
- `upload_items`: id, batch, photo file path, status, retry count, size, capture time.

The schema itself enforces integrity: foreign keys from photos to their batch (enabled on every connection), `CHECK` constraints on status values, and a partial unique index that allows only one draft batch.

**Batch flow:** photos go into the open *draft* batch as they are taken. **Upload batch** turns the draft into a *pending* batch, and the next photo starts a new draft, so any number of batches can wait in the queue. Statuses are `draft → pending → uploading → failed / completed`. The master plan's four upload statuses are extended with `draft`, the batch still being captured, which is never uploaded.

**Photo files:** the camera writes to the cache directory, which Android may clear at any time, so each photo is moved (an atomic rename) into app storage under `photos/<batch>/<photo>.jpg`. The database stores paths relative to that folder. If the record can't be written, the moved file is deleted, so no unreferenced file is left behind.

**Why SQLite rather than Hive:** the queue needs transactions, so that batch and photo statuses change together and a batch can be claimed for upload exactly once. It also needs safe access from a background isolate (the sync worker). SQLite provides both. Hive has no transactions and doesn't support multiple isolates.

Repository tests run real SQL through `sqflite_common_ffi`, including closing and reopening the database to check that the queue survives a restart. On the test phone, photos captured, queued and drafted were all still there after a force-stop and relaunch.

## Sync strategy

**Tether Capture**'s upload engine, `ProcessUploadQueue` (a pure-Dart domain use case), uploads due batches one at a time:

1. **Recover:** a batch left in *uploading* for longer than a 5-minute lease (the app was killed mid-upload) goes back to *pending*.
2. **Claim:** the oldest due batch (*pending*, or *failed* whose retry time has passed) is marked *uploading*. The read and update happen in one exclusive SQLite transaction, and the update only applies if the status is still the one just read. Only one worker can claim a batch. On Android, sqflite gives the app and a background worker isolate the same native connection and queues one isolate's calls while the other's transaction is open. A test with two independent workers claiming at the same time checks that no batch is taken twice. Removing the atomic claim makes that test fail with 12 claims for 6 batches.
3. **Upload** through `UploadApi.uploadBatch`, with the batch id as an idempotency key.
4. **Record the outcome:**
   - **Success:** the batch and its photos become *completed*. The photo files are deleted only after that is committed.
   - **Failure:** the batch becomes *failed*. Photos and records stay, the attempt is counted, the error is kept for display, and the next attempt is scheduled with exponential backoff (30 s, doubling, capped at 15 min).
   - **No connection:** the run stops, since every other batch would fail the same way.

Required invariant, covered by tests and checked on the test phone: **failed upload → images remain → queue records remain → retry possible.**

Overlapping triggers share one run. A batch submitted mid-run is picked up before the run ends. An unexpected API exception still counts as a failed attempt, so a batch is never left stuck.

**When uploads start:** on app launch, right after **Upload batch**, and on **Retry now** on Pending Uploads, which retries failed batches without waiting for their backoff. **Retry now** is a convenience only.

**Storage:** schema version 2 adds `next_attempt_at`. Existing installs are upgraded in place; this was checked on the test phone, whose queue was kept through the upgrade.

## Error handling

**Tether Attendance** handles two kinds of failure. Live-tracking problems are shown in the distance section, with Mark Attendance locked:

| Situation | Distance section shows |
|---|---|
| No permission | **Permission needed**, with an **Allow location** button |
| Location services off | **Location off**, with **Turn on location** |
| No fix for 15 s | **No GPS signal**, with advice to move near a window or outdoors |
| Fix worse than ±50 m | **Weak GPS signal** and the current accuracy |

Failures of a user action appear as a banner. Where the user can fix the cause, the banner offers that fix:

| Situation | Banner |
|---|---|
| Location permission denied | Explanation; tapping the button again asks again |
| Denied twice ("don't ask again") | Explanation and **Open settings** |
| Only approximate location granted | Precise location is required for a 50 m check, with **Open settings** |
| Location services off | **Turn on**, which opens location settings |
| No fix within 30 s when setting the office | Advice to retry with a clearer view of the sky |
| User moved, or fix went stale, between render and tap | Check-in refused; check the distance and retry |
| Storage write fails | Retry message; previous data is kept |

When the user returns from Settings having fixed the cause, the banner clears and tracking restarts automatically. Replacing an existing office location asks for confirmation first, because it moves the geofence.

**Tether Capture**, camera:

| Situation | What the user sees |
|---|---|
| Camera permission denied | Explanation and **Allow camera**, which asks again |
| Denied for good | Explanation and **Open settings**; returning with permission granted opens the camera automatically |
| No back camera | A message saying so |
| Camera fails to start (e.g. held by another app) | Explanation and **Try again** |
| A photo fails | A snackbar; the camera stays ready |

The app requests only the camera permission it needs. The camera plugin's microphone and storage permissions are removed from the manifest, because no audio is recorded and photos stay in app storage.

**Tether Capture**, upload queue:

| Situation | What the user sees |
|---|---|
| A photo can't be saved to the queue (e.g. storage full) | The same "couldn't take the photo" snackbar; nothing half-saved is left behind |
| Upload batch fails to write | A snackbar; the photos stay in the batch being captured |
| The queue can't be read | Pending Uploads says so |

**Tether Capture**, uploads:

| Situation | What the user sees |
|---|---|
| Upload fails (no internet, timeout, server error) | The batch shows "Failed once" (or "Failed N×"), the error, and when it is due again. Photos stay on the device, and **Retry now** is offered |
| Upload interrupted by the app closing | The batch returns to "Waiting to upload" with a note, and is retried |
| Upload succeeds | "Uploaded", and the photos are removed from the device |

## Mock API

The assessment provides no backend, so `MockUploadApi` implements `UploadApi`. It is a data-layer class; the UI only chooses its mode.

- **Real connectivity:** if the device has no network (e.g. airplane mode), every upload fails with "No internet connection", whatever the mode.
- **Modes**, chosen from **Mock server** on Pending Uploads and saved to a file so a background worker would use the same mode:

| Mode | Behaviour |
|---|---|
| Normal | Succeeds after a transfer time based on batch size (about 2 MB/s, at least 0.5 s) |
| Slow connection | About 16 KB/s, so a real photo batch times out after 8 s |
| Server error | Fails with 503 Service Unavailable |
| Unstable connection | About half of the uploads drop part-way |

- **Idempotent:** re-sending a batch it already stored returns the same receipt instead of storing it twice, which is what a real API must do with the batch-id key.

## Generative AI usage

_To be written._

## Toolchain

| | Version |
|---|---|
| Flutter / Dart | 3.44.6 (stable) / 3.12.2 |
| Android Gradle Plugin | 9.1.1 (native app uses AGP's built-in Kotlin) |
| Kotlin | 2.3.20 |
| Gradle | 9.3.1 (wrapper, checksum-pinned) |
| compileSdk / targetSdk | 37 / 36 |
| minSdk | 26 (Android) · 24 (Flutter) |
| JDK | 17 or newer |

## How to run

**Prerequisites:** JDK 17+, Android SDK 37, Flutter 3.44.x stable, and an Android device or emulator. A physical device is recommended for GPS and camera.

```bash
git clone <repository-url>
cd tether
```

### Tether Attendance (Android)

```bash
cd android-attendance
./gradlew installDebug
```

You can also open `android-attendance/` in Android Studio (2026.1 or newer) and run the `app` configuration.

### Tether Capture (Flutter)

```bash
cd flutter-capture
flutter pub get
flutter run
```

### Quality checks

```bash
# Android: formatting, lint, unit tests
cd android-attendance && ./gradlew ktlintCheck lintDebug testDebugUnitTest

# Flutter: formatting, static analysis, tests
cd flutter-capture && dart format --set-exit-if-changed lib test && flutter analyze && flutter test
```

## Screenshots

_To be added from the final build._

## Release APK

_To be added._

## Known limitations

**Tether Attendance**

- The map in the office card is a drawn placeholder. A real map SDK needs an API key, which the brief neither provides nor requires.
- There's no back arrow in the top bar: this is the app's only screen, so there's nowhere to go back to.
- The reference screenshot's "Available 09:00 AM – 10:30 AM" window isn't implemented, because the brief doesn't require a check-in time window. Attendance can be marked whenever the user is in range.
- Only the most recent check-in is stored; there is no history or server sync.
- Mock (spoofed) locations aren't detected.
- Any user can set the office location; in a real deployment this would be an administrator action.

**Tether Capture**

- The UI is locked to portrait, and photos are taken in portrait orientation.
- There is no front-camera switch or flash control; the brief asks for back-camera zoom and focus only.
- On Android the zoom shortcuts reflect what the main back camera exposes through its zoom range. Phones that show an ultra-wide lens only as a separate camera, not through zoom below 1x, get no 0.5x button.
- Individual photos can't be removed from a batch before upload.
- If the app is killed between moving a photo into storage and recording it (a few milliseconds), that file is left unreferenced. It is never uploaded, and only uses storage.
- Failed batches are not yet retried automatically when their retry time arrives or when the connection returns. They are retried on the next app launch, the next **Upload batch**, or **Retry now**.
- There is no upload percentage; a batch shows as uploading until it finishes.
- Uploaded batches stay listed (without their photos) until the app's data is cleared.
