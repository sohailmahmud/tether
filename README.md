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

### Main BLoC/Cubit classes

_To be written once the features are implemented._

## Local persistence

**Tether Attendance** uses Preferences DataStore, with two files that change independently:

- `office_location`: latitude, longitude, fix accuracy and save time, written in one transaction so a read never mixes old and new values. A missing, partial or out-of-range record reads as "no office set".
- `attendance`: the most recent check-in (time, distance from the office, fix accuracy), shown under the Mark Attendance button.

Both survive app restarts. Backup and device-to-device transfer are disabled for the app's data, so the geofence can't be moved by editing a backup.

_Flutter queue persistence: to be written once implemented._

## Sync strategy

_To be written once the features are implemented._

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

_Flutter: to be written once implemented._

## Mock API

_To be written once the features are implemented._

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
