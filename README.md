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
│       ├── data/                local storage, location source, repository implementations
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

The app has three layers: **presentation → domain → data**. Compose renders a single `StateFlow` of UI state, which a `ViewModel` exposes. The ViewModel calls domain use cases. Repositories hide the location provider and local storage behind interfaces. Dependencies are wired by hand: one screen does not justify a DI framework.

### Tether Capture (Flutter)

Layered architecture with BLoC/Cubit state management: **presentation (widgets + BLoC/Cubit) → domain → data**.

### Main BLoC/Cubit classes

_To be written once the features are implemented._

## Local persistence

_To be written once the features are implemented._

## Sync strategy

_To be written once the features are implemented._

## Error handling

_To be written once the features are implemented._

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

**Prerequisites:** JDK 17+, Android SDK 36, Flutter 3.44.x stable, and an Android device or emulator. A physical device is recommended for GPS and camera.

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
