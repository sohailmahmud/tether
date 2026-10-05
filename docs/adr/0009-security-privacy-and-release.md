# ADR-0009: Security, privacy and release posture

- **Status:** Accepted
- **Scope:** Both apps, repository and CI

## Context

The apps handle precise location and work photos. The repository is published publicly, and release builds must be signed without exposing signing secrets.

## Decision

**Least privilege.** Each app requests only what it uses:
- **Tether Attendance:** precise location, foreground only.
- **Tether Capture:** the camera.

Permissions that plugins add but the app doesn't use are removed from the merged manifest: the camera plugin's microphone and storage permissions, and the workmanager plugin's notification permission.

**Data stays on the device.** Cloud backup and device-to-device transfer are disabled in both apps:
- A restored office could be edited to move the geofence.
- A restored queue would no longer match the server.

**No secrets in version control:**
- Release signing reads git-ignored properties files, documented by `.example` templates. The keystore lives outside the repository.
- Without the properties files, release builds fall back to the debug key, so a fresh clone and CI still build installable APKs.
- CI holds no signing secrets.

**Release hardening:**
- The native app ships R8-shrunk, and the Flutter app AOT-compiled.
- State-transition logging is debug-only, because state can contain file paths.

**Published material:** README screenshots were taken with a simulated location and an emulator camera scene, so no real location or surroundings are published.

## Consequences

**Positive:**
- Minimal attack surface and permissions.
- Reproducible builds for reviewers.
- No credentials anywhere in the repository history, which was verified by a full-history scan.

**Negative:**
- Losing the keystore means future updates can't be signed as the same app, so it must be backed up outside the repository.
