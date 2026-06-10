---
title: Xcode update breaks simulator builds — no destinations despite Ready runtimes
date: 2026-06-10
category: build-errors
module: build-tooling
problem_type: build_error
component: tooling
symptoms:
  - "xcodebuild: error: Found no destinations for the scheme 'DOSBTSApp' and action build"
  - "Ineligible destinations list shows only 'Any iOS Device' with 'iOS 26.5 is not installed. Please download and install the platform'"
  - "xcrun simctl list devices hangs indefinitely (CoreSimulator 'Framework version does not match existing job version')"
  - "xcodebuild -showsdks lists the iphonesimulator SDK, and older runtimes show Ready — yet builds still fail"
resolution_type: environment_setup
severity: high
tags: [xcode-update, simulator-runtime, coresimulator, destinations, download-platform]
---

# Xcode update breaks simulator builds — no destinations despite Ready runtimes

## Problem

After macOS/Xcode updated to a new Xcode version (26.5), every simulator build failed with "Found no destinations for the scheme", blocking builds, tests, and deploys. Confusingly, `-showsdks` listed the matching simulator SDK and `simctl runtime list` showed older iOS runtimes (26.2/26.4) as `Ready`.

## Symptoms

- `xcodebuild ... -sdk iphonesimulator build` → `Found no destinations for the scheme`
- `xcodebuild -showdestinations` lists only the `Any iOS Device` placeholder as ineligible: "iOS 26.5 is not installed. Please download and install the platform from Xcode > Settings > Components."
- `xcrun simctl list devices` hangs forever; once kicked, logs `CoreSimulator detected version change. Framework version (1051.54) does not match existing job version (1051.50).`
- SDK present, old runtimes `Ready` — the error is about the *platform*, not the SDK

## What Didn't Work

- Passing an explicit `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'` — same no-destinations error; the devices exist but Xcode 26.5 refuses pre-update runtimes as build destinations
- `-destination 'generic/platform=iOS Simulator'` — same error
- Waiting out the hung `simctl` — it never returns while the stale CoreSimulator job is running

## Solution

Two stacked fixes, in order:

```bash
# 1. Un-wedge the stale CoreSimulator service left over from the Xcode update
#    (it auto-respawns with the new framework version)
killall -9 com.apple.CoreSimulator.CoreSimulatorService
xcrun simctl list devices   # should now return promptly

# 2. Download the new Xcode version's matching iOS platform (~8.5 GB, ~20 min)
xcodebuild -downloadPlatform iOS
xcrun simctl runtime list   # confirm e.g. "iOS 26.5 (23F77) ... (Ready)"

# 3. Build with an explicit destination on the new runtime
xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -configuration Debug build
```

Note: bare `-sdk iphonesimulator` (as the CLAUDE.md build commands used) hits the no-destinations error on this Xcode — use an explicit `-destination` instead.

## Why This Works

An Xcode update ships the new simulator **SDK** inside Xcode but not the simulator **platform/runtime**, which is a separate multi-GB download. Xcode requires its own matching-version runtime for build destinations and treats runtimes installed by the previous Xcode as ineligible — so "SDK listed + old runtimes Ready" still yields zero destinations. Separately, the update leaves the previous CoreSimulator service process running with a mismatched framework version, which makes every `simctl` call hang until the service is killed and respawns.

## Prevention

- After any Xcode update, before assuming code is broken: run `xcodebuild -downloadPlatform iOS` (or download via Xcode > Settings > Components) and expect the first `simctl` call to need a CoreSimulator restart
- Diagnostic order that separates the two failures: `xcodebuild -version` → `xcrun simctl runtime list` (hangs? → kill CoreSimulator) → `xcodebuild -showdestinations -scheme <scheme>` (ineligible-only? → download platform)
- `./deploy.sh` archive builds after an Xcode update likely need the device platform equivalent (`xcodebuild -downloadPlatform iOS` covers both) — budget the ~8.5 GB download into the first post-update deploy
- macOS has no `timeout` command by default — don't wrap the download in one; run it in the background and poll `xcrun simctl runtime list`

## Related Issues

- `docs/solutions/build-errors/ios-deployment-target-blocks-swift-api-cleanup-20260422.md` — earlier toolchain/deployment-target friction in the same area
