# ADR-0002: Unidirectional state management per platform

- **Status:** Accepted
- **Scope:** Presentation layer of both apps

## Context

The brief requires Kotlin Flow on Android and BLoC/Cubit on Flutter. Both apps combine asynchronous sources:
- **Attendance:** live location, persisted office and check-in data, and in-flight user actions.
- **Capture:** camera hardware, the persistent queue, connectivity, and upload progress.

UI state must stay consistent across configuration changes, lifecycle transitions and background work.

## Decision

**Android: one `StateFlow` per screen.**
- `AttendanceViewModel.uiState` is built by `combine`-ing the attendance status, the last check-in and a small `MutableStateFlow` of in-flight actions and errors.
- It is shared with `SharingStarted.WhileSubscribed(5_000)` and collected with `collectAsStateWithLifecycle`. GPS therefore runs only while the screen is visible, and survives configuration changes.
- `AttendanceScreen` is stateless: it renders `AttendanceUiState` and reports intents through `AttendanceActions`.

**Flutter: one Cubit per concern, each with an immutable `Equatable` state.**

| Cubit | Responsibility |
|---|---|
| `CameraCubit` | Camera lifecycle and controls (sealed `CameraState`) |
| `UploadQueueCubit` | Streams the persistent queue |
| `SyncCubit` | Upload triggers, connectivity and per-batch progress |
| `MockServerCubit` | Demo server mode |

Widgets read state with `BlocBuilder` and `context.select`, and call Cubit methods for intents.

## Consequences

**Positive:**
- **Single source of truth:** persisted data reaches the UI through streams, never through hand-copied fields.
- **Deterministic tests:** ViewModel and Cubit transitions are tested with `kotlinx-coroutines-test` and `bloc_test`, and timers run in virtual time (`fake_async`).
- **Lifecycle-aware by construction:** no work runs for invisible screens.

**Negative:**
- Cubits use methods rather than event classes, so there are no event transformers such as debounce or droppable. The few places that need serialization or de-duplication (camera operations, overlapping sync triggers) implement it explicitly and test it.

## Alternatives considered

- **`Bloc` with event classes:** more ceremony than these intents need. Cubit is part of the same library and keeps the BLoC contract.
- **Riverpod or Provider (Flutter), MVI frameworks (Android):** outside the brief's stated stack, with no benefit at this scale.
