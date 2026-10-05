# ADR-0001: Two applications, one per task

- **Status:** Accepted
- **Scope:** Repository, build and delivery

## Context

The assessment defines two tasks with different, explicit platform requirements:

- **Task 1** is native Android: Jetpack Compose and Kotlin Flow.
- **Task 2** is Flutter: BLoC/Cubit and a layered architecture.

The brief asks for a release APK link. It does not ask for the two tasks to be integrated into one product.

## Decision

Deliver two independent applications in one repository:

| App | Folder | Stack |
|---|---|---|
| Tether Attendance | `android-attendance/` | Kotlin, Jetpack Compose, Kotlin Flow |
| Tether Capture | `flutter-capture/` | Flutter, BLoC/Cubit |

Each app has its own build, test suite, CI workflow and signed release APK. The two share only brand, design conventions and engineering standards.

## Consequences

**Positive:**
- Each task uses its platform's idiomatic stack, with no integration layer to maintain.
- Builds, tests and releases are independent, so a change to one app can't break the other.
- CI runs per app, scoped by path filters.

**Negative:**
- Reviewers install two APKs.
- No code is shared between the apps, but none needs to be.

## Alternatives considered

- **Flutter add-to-app inside the native app (one APK):** rejected. It adds build complexity, a larger binary and lifecycle coupling between two runtimes, for an integration the brief doesn't require.
- **Two repositories:** rejected. A single repository keeps the submission, documentation and CI in one place.
