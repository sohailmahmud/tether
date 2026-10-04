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
- **Domain:** models (`OfficeLocation`, `LocationData`), repository interfaces, and `SetOfficeLocationUseCase`, which takes a fresh fix and saves it as the office. `AttendancePolicy` is the only place the 50 m radius is defined.
- **Data:** `FusedLocationRepository` (Google Play services location) and `DataStoreOfficeLocationRepository`. Each data source has exactly one repository, so the repository lives next to its source instead of in a separate pass-through layer.

The ViewModel reads the saved office straight from the repository's `Flow`, which makes storage the single source of truth: a successful save reaches the screen through that flow. A use case exists only where there is logic to coordinate. Dependencies are wired by hand in `AppContainer`, because one screen and two repositories don't justify a DI framework.

### Tether Capture (Flutter)

Layered architecture with BLoC/Cubit state management: **presentation (widgets + BLoC/Cubit) → domain → data**.

### Main BLoC/Cubit classes

_To be written once the features are implemented._

## Local persistence

**Tether Attendance:** the office location is kept in Preferences DataStore (`office_location`): latitude, longitude, fix accuracy and save time. All four are written in one transaction, so a read never mixes old and new values. A missing, partial or out-of-range record reads as "no office set". Backup and device-to-device transfer are disabled for the app's data, so the geofence can't be moved by editing a backup.

_Flutter queue persistence: to be written once implemented._

## Sync strategy

_To be written once the features are implemented._

## Error handling

**Tether Attendance:** every failure becomes a banner on the screen. Where the user can fix the cause, the banner offers that fix.

| Situation | What the user sees |
|---|---|
| Location permission denied | Explanation; tapping Set Office Location asks again |
| Denied twice ("don't ask again") | Explanation and **Open settings** |
| Only approximate location granted | Precise location is required for a 50 m check, with **Open settings** |
| Location services off | **Turn on**, which opens location settings |
| No fix within 30 s | Advice to retry somewhere with a clearer view of the sky |
| Storage write fails | Retry message; the previous office is kept |

When the user returns from Settings having fixed the cause, the banner clears automatically. Replacing an existing office location asks for confirmation first, because it moves the geofence.

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

_To be written._
