---
title: Injecting UserDefaults into a simulator app requires the app-container plist path, not the bundle-id domain
date: 2026-06-11
category: best-practices
module: testing/simulator tooling
problem_type: developer_experience
component: development_workflow
severity: medium
applies_when:
  - "Injecting app state (treatment cycle, consent flags, alarm thresholds) into the simulator for manual testing"
  - "A simctl defaults write appears to succeed but the app never sees the value"
tags: [simctl, userdefaults, simulator, defaults-write, app-container, testing]
---

# Injecting UserDefaults into a simulator app requires the app-container plist path, not the bundle-id domain

## Context

Reproducing treatment-cycle and consent states in the simulator (builds 99–101 verification) needed UserDefaults injection. The obvious command silently writes to the wrong place.

## Guidance

`xcrun simctl spawn <udid> defaults write <bundle-id> key value` writes to a device-level preferences domain that the **sandboxed app never reads** — `defaults read` shows the value, the app behaves as if nothing was set. Write to the app container's plist instead, with the app terminated:

```bash
UDID=...; BID=com.cinimody.eatthisidie
xcrun simctl terminate $UDID $BID
DATA=$(xcrun simctl get_app_container $UDID $BID data)
PLIST="$DATA/Library/Preferences/$BID.plist"
xcrun simctl spawn $UDID defaults write "$PLIST" "libre-direct.settings.treatment-cycle-active" -bool true
xcrun simctl launch $UDID $BID
```

Diagnostic for the wrong-domain trap: `defaults read <bundle-id>` shows ONLY your injected keys (none of the app's real settings) — the app's actual store is the container plist.

## Why This Matters

The wrong-domain write fails silently and reads back successfully, which makes it look like the app is ignoring valid state. This burned a full reproduce-launch-inspect loop before the container listing (only 2 keys in the domain vs a full settings plist in the container) exposed it.

## When to Apply

Any time test state is injected into a simulator app via UserDefaults — treatment cycles, consent flags, alarm thresholds, migration gates. Terminate the app before writing; relaunch after.

## Examples

DOSBTS keys live under `libre-direct.settings.*` (see `Library/Extensions/UserDefaults.swift` `Keys`). Treatment-cycle injection needs both `treatment-cycle-active` (bool) and `treatment-cycle-countdown-expiry` (epoch float).
