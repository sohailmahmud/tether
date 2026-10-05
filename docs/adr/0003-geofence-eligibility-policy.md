# ADR-0003: Geofence eligibility as a single domain policy

- **Status:** Accepted
- **Scope:** Tether Attendance domain layer

## Context

Attendance may be marked only within 50 m of the saved office.

- **GPS is noisy:** indoor accuracy commonly varies between ±10 m and ±70 m.
- **Fixes go stale:** the signal can drop without the provider reporting it.
- **The screen can lag:** the user may move between the render and the tap.

The brief asks for "high accuracy" without defining a threshold.

## Decision

One pure function, `AttendancePolicy.evaluate(office, fix)`, decides eligibility:

| Rule | Value |
|---|---|
| Radius | 50 m, inclusive; haversine distance |
| Accuracy | The fix must be ±50 m or better. A fix less certain than the geofence can't tell inside from outside |
| Freshness | A fix older than 15 s (measured on the monotonic clock) no longer counts |

The same rules apply in three places:
- **Display:** the screen uses the policy to enable Mark Attendance.
- **Check-in:** `MarkAttendanceUseCase` re-validates eligibility and freshness at the moment of the tap.
- **Office capture:** `SetOfficeLocationUseCase` rejects fixes worse than ±50 m, because an imprecise office would shift the whole geofence.

Displayed distances are rounded **up**, so the label always agrees with the rule. For example, 50.2 m shows as "51m", out of range.

## Consequences

**Positive:**
- One testable rule, with boundary tests at 49.99 m and 50.01 m.
- A stale screen can never record an invalid check-in.

**Negative:**
- Users indoors may see "Weak GPS signal" until accuracy improves. This is the intended trade-off: a check-in is only accepted from a fix precise enough to trust.

## Alternatives considered

- **Android Geofencing API (`GeofencingClient`):** rejected. It targets background enter and exit transitions, and Google recommends a minimum radius of 100–150 m with delivery latency. It cannot drive a live, on-screen 50 m distance check.
- **Trust the button state alone:** rejected. The button reflects the last render, not the moment of the tap.
