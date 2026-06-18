---
date: 2026-06-18
topic: tight-control-streak-celebration
---

# Tight-Control Streak Celebration — Requirements

## Summary

When glucose holds inside the clinical-ideal band (80–120 mg/dL) for 2+ continuous hours, DOSBTS marks the moment with a "TIGHT CONTROL" toast — phosphor chime, haptic, DOS amber styling — and tracks a lifetime count on the STATISTICS view. It is reward-only, can be switched off in Settings, and stays quiet (visual only) during night-profile hours. Tracks Linear DMNC-772; adapts the DOOMBTS "secret area" mechanic to the DOS aesthetic.

## Problem Frame

DOSBTS today only ever tells the user when something is *wrong* — alarms for highs, lows, predictive-low trends, sensor failures, stale data. There is no signal for doing well. A person managing diabetes lives inside an app that nags and never nods. The cost is motivational, not functional: sustained tight control is the hardest and most thankless part of the work, and the app is silent for exactly the behaviour it should reinforce. This feature is the app's first positive-feedback loop — a small, deliberately low-key moment of recognition for the stretches that go right.

## Key Decisions

- **Reward-only, no anxiety.** The feature only ever adds a positive moment. It never messages streak loss, never warns "you're about to break tight control", never frames the band as a target the user is failing. The 80–120 band is aspirational, not prescriptive.
- **Hysteresis re-arm to prevent flicker-spam.** A celebration fires at most once per genuine streak. After firing, the detector re-arms only once glucose leaves the band by a margin (default ≥5 mg/dL beyond an edge — i.e. below ~75 or above ~125), so a 119↔121 wobble can't trigger repeat celebrations. Exact margin tuned in planning.
- **Deferred presentation, not interruption.** Detection runs whenever readings arrive (including backgrounded). Presentation (toast + sound + haptic) waits until the app is next in the foreground. A streak completed while the app is closed is shown on next open, never as a push notification.
- **Persisted dedup — not an in-memory flag.** The "already celebrated this streak" state and the lifetime count persist across app kill. This is required precisely because detection is retroactive on launch (the reading stream replays loaded history); an in-memory flag like the DOOMBTS reference would re-fire an already-earned celebration on every relaunch.
- **Sound follows display time, not achievement time.** A streak earned at 03:00 is shown silently if surfaced during night-profile hours, or with the chime if the user opens the app at 08:00. The "quiet at night" rule is evaluated at the moment of presentation.
- **Fixed thresholds.** 80–120 mg/dL and 2 hours are not user-configurable.
- **Single feature gate.** The Settings toggle (default ON) gates the whole feature — detection, counter increment, and presentation. While off, nothing accrues and the lifetime count does not move.
- **No treatment-cycle special-casing.** An active hypo treatment cycle needs no explicit suppression: a low excludes you from the 80–120 band, so the streak naturally cannot accrue during one, and a fresh 2h streak only starts after recovery.

## Requirements

**Detection**

- R1. Detect when sensor glucose stays within 80–120 mg/dL (inclusive, mg/dL internal value) for ≥2 continuous hours, evaluated as readings arrive.
- R2. A reading outside 80–120 breaks the in-progress streak; accrual restarts on the next in-band reading.
- R3. A data gap longer than a threshold (default to be set in planning, on the order of a few sensor intervals) breaks the in-progress streak — a stretch with no readings cannot count toward continuous tight control.
- R4. After a celebration fires, the detector re-arms (becomes eligible to fire again) only after glucose has left the band by the hysteresis margin; brief single-reading excursions that return immediately do not re-arm.

**Celebration surfaces**

- R5. On a qualifying streak, present a transient "TIGHT CONTROL" toast in the DOS amber aesthetic (DOSTypography display weight, amber/cyan tokens), auto-dismissing after a few seconds.
- R6. Pair the toast with a short distinctive phosphor-chime sound and a success haptic, subject to R10 (quiet at night) and the device mute switch.
- R7. Maintain a lifetime count of tight-control achievements and surface it as a stat on the STATISTICS report view alongside AVG/SD/CV/GMI.

**Persistence & dedup**

- R8. Each qualifying streak produces at most one celebration and at most one lifetime-count increment, with no duplicate fire across app backgrounding, kill, relaunch, or retroactive re-processing of the same readings.
- R9. The lifetime count and the dedup/arming state persist across app kill.

**Settings, quiet hours, accessibility**

- R10. During night-profile hours (reusing the existing day/night alarm-profile schedule), celebrations are visual only — no sound, no haptic. Evaluated at presentation time.
- R11. A "Celebrations" Settings toggle (default ON) gates the entire feature; while OFF, no detection, presentation, or count increment occurs.
- R12. Respect `UIAccessibility.isReduceMotionEnabled`: spring/entry animation degrades to a static or linear appearance when reduce-motion is on.

## Key Flows

- F1. Foreground achievement
  - **Trigger:** A new in-band reading arrives that completes a 2h streak while the app is active and armed.
  - **Steps:** Detector confirms streak → increments lifetime count (R7) → marks streak celebrated (R8) → presents toast + chime + haptic (R5, R6) subject to quiet-hours (R10) → toast auto-dismisses → detector disarms until re-arm condition (R4).
  - **Covers:** R1, R4, R5, R6, R7, R8, R10.

- F2. Backgrounded achievement → deferred toast
  - **Trigger:** A streak completes while the app is backgrounded or closed.
  - **Steps:** Detection runs on arriving/loaded readings → count increments and a pending-celebration marker is persisted (R8, R9) → on next foreground, the pending celebration is presented once (R5, R6) with sound governed by display-time quiet-hours (R10) → marker cleared.
  - **Covers:** R8, R9, R10.

- F3. Relaunch with no double-fire
  - **Trigger:** App relaunches and the reading stream replays history that includes an already-celebrated streak.
  - **Steps:** Detector re-evaluates → persisted dedup state recognises the streak as already celebrated → no toast, no increment.
  - **Covers:** R8, R9.

## Acceptance Examples

- AE1. **Covers R1, R5.** Given 24 consecutive 5-min readings all in 80–120, when the 2h mark is reached with the app foregrounded, then one "TIGHT CONTROL" toast appears with chime + haptic.
- AE2. **Covers R2, R4.** Given a celebration has fired and glucose then reads 121 once and returns to 118, then no new celebration fires (121 did not exceed the hysteresis margin to re-arm), even after a fresh 2h in-band stretch.
- AE3. **Covers R4.** Given a celebration has fired, when glucose later rises above ~125 (beyond the margin) and then returns and holds 80–120 for 2h, then a second celebration fires.
- AE4. **Covers R3.** Given 90 min in-band, then a 40-min reading gap, then in-band readings resume, when 2h of *continuous* in-band time has not been re-accrued, then no celebration fires; the streak counts only from the resumed readings.
- AE5. **Covers R8, R9.** Given a streak completed while the app was closed, when the app opens, then exactly one deferred toast appears and the lifetime count has increased by exactly one; reopening the app again shows no further toast and no further increment.
- AE6. **Covers R10.** Given a streak completes during night-profile hours, when presented, then the toast appears with no sound and no haptic.
- AE7. **Covers R11.** Given the Celebrations toggle is OFF, when a 2h in-band streak occurs, then nothing is shown and the lifetime count does not change.

## Scope Boundaries

**Deferred for later**
- Configurable band/duration, multiple achievement tiers, per-day or current-streak displays beyond the single lifetime count.
- Live Activity / widget / lock-screen reflection of the achievement.
- A local notification path for backgrounded achievements (explicitly traded away for deferred toast; revisit only if dogfooding shows the deferred toast is too easy to miss).

**Outside this product's identity**
- Streak-loss or "don't break it" messaging, countdown-to-failure framing.
- Leaderboards, social sharing, or any comparison against other users.

## Dependencies / Assumptions

- **Assumption (unverified):** the sensor-connection layer processes BLE readings and dispatches the glucose-add action while the app is backgrounded, so detection can run live in the background. If it does not, F2 still holds via retroactive detection on next launch — but this should be confirmed during planning, as it changes how "deferred" behaves.
- **Reuse:** the existing day/night alarm-profile schedule defines night hours for R10 — no new schedule UI.
- **Reuse:** existing sound-playback + haptic helpers and the bundled retro/phosphor audio assets; selecting or adding the specific chime is a planning task.
- **Reuse:** the existing 4-file UserDefaults-backed settings pattern for R11 and the STATISTICS report view for R7.

## Outstanding Questions

**Deferred to planning**
- Exact hysteresis margin value (R4) and exact data-gap threshold (R3).
- The dedup key/mechanism that satisfies R8 across retroactive replay (e.g. a persisted high-water mark vs. a per-streak identity).
- Which bundled audio asset is the "phosphor chime", or whether to add a new one.
- Banner sub-line copy beneath "TIGHT CONTROL" (e.g. "2 HOURS IN RANGE") and exact STATISTICS card label.
- Which Settings category hosts the toggle (Alarms & Alerts vs. a dedicated row).

## Sources / Research

DOSBTS integration points (verified during grounding):
- Reading stream: `.addSensorGlucose` dispatched from `App/Modules/SensorConnector/SensorConnector.swift`; state history in `state.sensorGlucoseValues`, model `Library/Content/SensorGlucose.swift` (mg/dL internal value, `timestamp`, `minuteChange`).
- Middleware registration: both arrays in `App/App.swift` (device + simulator) must be updated; mirror `App/Modules/TreatmentCycle/TreatmentCycleMiddleware.swift` as the reference observer of `.addSensorGlucose`.
- Transient UI: `App/Views/Overview/TreatmentBannerView.swift` (auto-dismiss) and `App/Views/SharedViews/LoggedMealToast.swift` (`LoggedMealToastController` overlay pattern).
- Sound + haptics: `Library/DirectNotifications.swift` (`playSound`, `hapticFeedback`/`hapticNotification`); assets under `Library/Resources/` (`.aiff`).
- STATISTICS: `App/Views/Lists/StatisticsView.swift` + `GlucoseStatistics` in `Library/Content/SensorGlucose.swift`.
- Night window: day/night alarm-profile schedule (`Library/Content/AlarmProfile.swift`, profile schedule properties on app state).
- Settings pattern: `Library/DirectState.swift`, `App/AppState.swift`, `Library/Extensions/UserDefaults.swift`, `Library/DirectReducer.swift`.

DOOMBTS reference (sibling fork, `../DOOMBTS`):
- `docs/brainstorms/2026-04-20-secret-area-discovery-requirements.md`, `docs/plans/2026-04-20-002-feat-secret-area-discovery-plan.md`, `GameMechanicsMiddleware`. Key divergence to carry forward: DOOMBTS used an in-memory closure flag for one-shot dedup (re-fires on relaunch) and respected neither reduce-motion nor quiet hours — R8/R9/R10/R12 deliberately close those gaps.
