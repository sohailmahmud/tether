# Changelog

All notable changes to this project are documented in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and both apps use [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-10-06

First release of both apps.

### Tether Attendance (Android)

**Office location**
- Set Office Location from a fresh high-accuracy fix (±50 m or better), persisted in Preferences DataStore.
- Replacing an existing office asks for confirmation.

**Check-in**
- Mark Attendance is enabled only within 50 m of the office, and re-validated at the moment of the tap.
- A fix older than 15 s no longer counts.

**Live distance**
- A distance ring and range status update every 2 s while the screen is visible.

**Failure states**
- Clear states for missing or permanently denied permission, approximate-only location, location services off, no GPS signal and weak accuracy.
- Each one offers its fix where one exists, and the screen recovers automatically on return from Settings.

### Tether Capture (Flutter)

**Camera**
- A custom camera with pinch, slider and rounded zoom buttons derived from the device's zoom range.
- Tap-to-focus with a focus indicator.
- Lifecycle-safe camera ownership.

**Batch capture**
- Captured photos are kept in a persistent SQLite queue.
- The Upload Manager lists pending, failed and uploaded batches, with determinate upload progress.

**Resilient sync**
- An upload engine with atomic claims, leases, idempotency keys and exponential backoff.
- Automatic retry on a stable reconnection.
- A WorkManager background worker with a network constraint, which completes uploads after the app is closed.

**Mock API**
- Normal, slow-connection, server-error and unstable modes, selectable in the app.

**Platform**
- An adaptive app icon.
- Least-privilege permissions.
- Cloud backup disabled.

### Engineering

- **Tests:** 222 automated tests — 85 Android (domain, persistence, ViewModel, Compose UI) and 137 Flutter (domain, real SQL, Cubits, widgets, end-to-end app flows).
- **CI:** GitHub Actions workflows for both apps: formatting, lint and analysis, tests and release builds.
- **Release signing:** from git-ignored properties files, falling back to the debug key for reviewers.
- **Documentation:** architecture decision records in `docs/adr/`.

[1.0.0]: https://github.com/sohailmahmud/tether/releases/tag/v1.0.0
