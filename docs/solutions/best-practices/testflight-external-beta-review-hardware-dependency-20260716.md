---
title: "TestFlight external Beta App Review can't exercise a hardware-only CGM app — ship honest review notes, not a demo mode"
date: 2026-07-16
category: best-practices
module: deploy
problem_type: best_practice
component: TestFlight/ASC submission
severity: medium
applies_when:
  - "Submitting a build for EXTERNAL TestFlight Beta App Review (external groups trigger Apple review; internal testing does not)"
  - "The app's core function needs physical hardware the reviewer won't have (a FreeStyle Libre sensor or Bubble transmitter)"
  - "Deciding whether to build a reviewer-only demo/simulator path before submitting"
tags:
  - deploy
  - testflight
  - app-store-connect
  - beta-review
  - sensor-connection
---

# TestFlight external Beta review of a hardware-only app

## Context

External TestFlight distribution requires Apple's **Beta App Review**; internal
testing (your ASC team, up to 100 users) does not. Apple's reviewer runs the
build on a real device **with no glucose sensor**, and a Release/device build of
DOSBTS gives them no way to see live data:

- `VirtualLibreConnection` — the simulated sensor that feeds fake glucose — is
  registered **only** inside a simulator guard: `#if targetEnvironment(simulator)`
  wraps the second (simulator) middleware array, and the Virtual connection is
  appended at `App/App.swift:249` (`SensorConnectionInfo(id: DirectConfig.virtualID, name: "Virtual") { VirtualLibreConnection(subject: $0) }`), inside the block opened at `App/App.swift:198`.
- The `LibreLink` cloud connection (which could pull data without local hardware)
  is gated behind `if DirectConfig.isDebug` (`App/App.swift:316`); `isDebug` is
  false for Release/TestFlight archives (`Library/DirectConfig.swift:77`).
- So a TestFlight build offers only `Libre2` direct ("Without transmitter",
  `App/App.swift:306`, needs NFC + a physical Libre 2) and `Bubble`
  (`App/App.swift:307`, needs transmitter hardware). Both require hardware.

The reviewer can launch the app, navigate, and open every Settings screen, but
cannot pair a sensor or see a reading. This is the usual reason a
hardware-companion app bounces from review.

## Guidance

For a build like this, **submit as-is with honest review notes** rather than
building a reviewer demo mode. Beta App Review is lighter than full App Store
review and routinely approves hardware-dependent apps when the notes are clear.
Put these in the **Beta App Review Information → Review Notes**:

1. State plainly that live data needs a **physical** FreeStyle Libre 2 (NFC/BLE)
   or Bubble transmitter, and that without one the reviewer sees no readings.
2. State what **is** exercisable without hardware: onboarding, navigation, and
   all of Settings.
3. Set **Sign-in required: No** — the app is local-only; no account/login.
4. Confirm export compliance is already declared, so there's no per-build
   encryption question: `ITSAppUsesNonExemptEncryption` is set in
   `App/Info.plist:38` (value `false`).
5. Provide the live **Privacy Policy URL** (external review requires one):
   `https://dosbts.dmnc.tech/privacy`.

If it's rejected for "couldn't evaluate functionality," you still have two
no-code moves before writing a demo mode: **reply in Resolution Center**
reiterating the hardware dependency (often clears it), or **fall back to
internal testing** (no review at all) if the point is just solo dogfooding.

## Why This Matters

A reviewer-reachable simulator sensor in Release builds would remove the risk
entirely, but it's real code (lift `VirtualLibreConnection` out of the
`targetEnvironment(simulator)` guard behind a safe, discoverable-only toggle)
and carries its own risk of shipping a fake-data path to end users. For a
personal/experimental app, that cost isn't worth paying pre-emptively — honest
notes are cheaper and usually sufficient. Know the trade before you reflexively
build a demo mode.

## When to Apply

Any external Beta submission where core functionality depends on hardware,
a companion device, a paired account on another device, or a backend the
reviewer can't reach. Internal-only testing sidesteps review entirely and needs
none of this.

## Examples

Review-notes text that passed for Build 131 (Waiting for Review, 2026-07-16):

```
DOSBTS is a personal, experimental companion app for FreeStyle Libre continuous
glucose monitoring (CGM) sensors. It is not a medical device.

HARDWARE REQUIRED FOR LIVE DATA: The app shows glucose readings by connecting to
a physical FreeStyle Libre 2 sensor (NFC/Bluetooth) or a Bubble transmitter.
Without a paired physical sensor, live readings and charts cannot be exercised on
the review device. Everything else — onboarding, navigation, and all of Settings
(Alarms & Alerts, Insulin/Ratios, Glucose & Display, Sensor & Connection) — is
fully explorable without hardware.

No account or login is required; data is stored locally (and optionally in Apple
Health). The app requests Bluetooth, NFC, notification, and Health permissions;
these can be declined without crashing the app.
```

Contrast — the failure mode this avoids: submitting with empty/boilerplate notes,
the reviewer opens the app, sees no data (no sensor), and rejects for guideline
2.1 "couldn't evaluate the app's features."
