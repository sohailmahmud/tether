# ADR-0008: Composition roots and manual dependency injection

- **Status:** Accepted
- **Scope:** Both apps

## Context

Both apps have small object graphs:
- **Tether Attendance:** one screen and three repositories.
- **Tether Capture:** two screens, four Cubits and one engine.

The graphs must be easy to substitute in tests: fakes at the hardware, network and storage edges.

## Decision

Wire dependencies by hand in explicit composition roots:

- **Android:** `AppContainer`, owned by the `Application`, creates repositories and use cases. The ViewModel factory reads from it.
- **Flutter:**
  - `main.dart` builds the concrete implementations.
  - `SyncDependencies` builds the upload engine identically for the app and for the background worker.
  - `TetherCaptureApp` receives everything through its constructor.
  - The presentation layer never imports plugins; the camera preview is injected as a builder.

## Consequences

**Positive:**
- No reflection, code generation or framework conventions to learn, and the wiring reads top to bottom.
- Tests inject fakes at the same seams. App-flow tests run the real `TetherCaptureApp` with only the edges faked.

**Negative:**
- A much larger graph would justify a framework. The roots are the single place where that change would happen.

## Alternatives considered

- **Hilt or Koin (Android), `get_it` or `injectable` (Flutter):** rejected. Their setup costs exceed their benefit at this size.
