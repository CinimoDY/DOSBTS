# DOSBTS

> **D**OS **O**n **S**ugar — **B**uilt **T**o **S**ee. A DOS amber CGA aesthetic fork of [GlucoseDirect](https://github.com/creepymonster/GlucoseDirectApp) for reading Libre CGM sensors on iOS.

> ⚠️ **This app is highly experimental. Do not make dosing decisions based on software alone.** It does not replace a medical device or the advice of a healthcare professional.

![iOS 26](https://img.shields.io/badge/iOS-26+-FFB000?style=flat-square)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-FFB000?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-FFB000?style=flat-square)

## Screenshots

| Overview | Daily digest |
|:---:|:---:|
| <img src="Screenshots/dosbts-overview.png" alt="Overview with glucose chart, event marker lane, and IOB overlay" width="280"> | <img src="Screenshots/dosbts-digest.png" alt="Daily digest stats grid and AI insight narrative" width="280"> |
| **Meal entry** | **Settings** |
| <img src="Screenshots/dosbts-meal-entry.png" alt="Unified meal entry with a QUICK favourites section plus Manual, Scan, Photo, and Ask AI paths" width="280"> | <img src="Screenshots/dosbts-settings.png" alt="Glucose settings panel" width="280"> |

<sub>Build 61 on TestFlight. Overview, digest, and meal entry are on-device with real data; settings is a simulator capture.</sub>

## What it is

DOSBTS is a personal fork of Reimar Metzen's excellent [GlucoseDirect](https://github.com/creepymonster/GlucoseDirectApp) — a SwiftUI CGM app for Libre sensors — re-skinned as a 1985-style amber phosphor DOS terminal and then extended with food logging, insulin-on-board, AI-assisted meal analysis, and a guided hypo treatment workflow.

The idea: make diabetes UX feel like a dedicated instrument you own, not a service you rent. CRT glow, monospace type, sharp corners, and exactly the right amount of DOS nostalgia.

## Heritage and credit

Everything good about this app that isn't amber is thanks to [Reimar Metzen / @creepymonster](https://github.com/creepymonster). The sensor-connection stack (Libre 1/2/3, Bubble, LibreLinkUp), calibration math, Nightscout integration, Apple Watch calendar export, HealthKit export, and the entire Redux-like architecture were all his work. DOSBTS inherits all of that under MIT.

If you use DOSBTS, please consider **supporting the upstream project first** via [creepymonster's PayPal](https://www.paypal.me/creepymonstr) — the foundation this is built on is enormous. A sister fork, [DOOMBTS](https://github.com/CinimoDY/DOOMBTS), explores the same codebase in a Doom-inspired aesthetic.

## What's new in DOSBTS (vs. GlucoseDirect upstream)

### Visual identity
- **Amber CGA phosphor aesthetic** — `#FFB000` primary, pure black backgrounds, SF Mono throughout, optional CRT scanline overlay
- **Phosphor-style home screen widget** — rewritten widget (sparkline, IOB, TIR, last meal) with the amber glow treatment
- **Event marker lane** — meals, insulin, exercise icons on their own lane above the glucose chart

### Food logging
- **Unified meal entry** — favorites, recents, and type-ahead search in one view
- **AI food analysis** — photo, natural-language text, and barcode (Open Food Facts) input paths, powered by Claude Haiku. Requires explicit user consent.
- **Conversational follow-up** for low-confidence AI parses
- **Editable AI results** — the app learns from your corrections via a `PersonalFood` glycemic database
- **Meal impact overlay** — tap a meal marker to see its 2-hour post-meal glucose delta, confounder detection, and rolling glycemic score

### Insulin & dosing
- **Insulin-on-Board (IOB)** — OpenAPS oref0 exponential decay model, hero display with 60s refresh, chart overlay (iOS 16+), stacking warning in the bolus flow
- **Insulin settings** — rapid-acting vs. ultra-rapid presets, configurable basal DIA (2–24h), optional split meal/basal display

### Alarms & treatment
- **Guided hypo treatment workflow** ("Rule of 15") — alarm → log treatment → 15-min countdown → recheck glucose → stabilised or treat again. Background-safe via UNNotification actions.
- **Predictive low alarm** — 20-min forward extrapolation of glucose trajectory using smoothed minute-change, with a dashed projection line on the chart
- **Stale data indicator** — warns when the latest reading is >5 min old
- **Insulin, carbs, exercise overlays** on the chart

### Daily digest
- **Daily digest tab** — per-day stats, AI-generated insight (Haiku), and an event timeline for the day

## Requirements

- iPhone on **iOS 26** or later
- A compatible Libre sensor (Libre 1 with Bubble transmitter, Libre 2 EU, Libre 3 via LibreLinkUp)
- Xcode 16+ to build

## Quick test

A TestFlight link will be posted here when it's stable enough for external testers. Until then, build locally with `./deploy.sh` (requires an Apple developer account).

## Development

```bash
# Build app
xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -configuration Debug build

# Build widget
xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSWidget -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -configuration Debug build

# Tests (262 passing as of build 96)
xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```

The Xcode project uses `fileSystemSynchronized` groups — new `.swift` files under `App/`, `Library/`, or `Widgets/` are auto-picked up. See `CLAUDE.md` for the full architecture notes.

## Support

If DOSBTS is useful to you:

1. **First**, support [creepymonster / GlucoseDirect](https://www.paypal.me/creepymonstr) — the project this is built on
2. If you also want to say thanks for the DOSBTS fork specifically (AI tokens, subscription costs, time): [GitHub Sponsors → CinimoDY](https://github.com/sponsors/CinimoDY)

No obligation either way. Pull requests and issue reports are the most valuable form of support.

## FAQ

Most of the sensor / connection / LibreLinkUp content in upstream's [FAQ](https://github.com/creepymonster/GlucoseDirect/blob/main/FAQ.md) still applies.

## License

[MIT](LICENSE.md). Original copyright © 2023 Reimar Metzen. DOSBTS fork additions © 2026 Dominic Kennedy.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the release history since forking (2026-02-28 → present, TestFlight builds 2–61).

## Sound credits

Inherited from upstream GlucoseDirect. All sounds used under CC0 1.0 Universal or CC Attribution 3.0 Unported:

- SpliceSound — [369848](https://freesound.org/people/SpliceSound/sounds/369848) (CC0)
- JavierZumer — [257227](https://freesound.org/people/JavierZumer/sounds/257227), [257235](https://freesound.org/people/JavierZumer/sounds/257235) (CC-BY 3.0)
- LorenzoTheGreat — [417791](https://freesound.org/people/LorenzoTheGreat/sounds/417791) (CC-BY 3.0)
- LittleRobotSoundFactory — [270329](https://freesound.org/people/LittleRobotSoundFactory/sounds/270329/), [270327](https://freesound.org/people/LittleRobotSoundFactory/sounds/270327/), [270323](https://freesound.org/people/LittleRobotSoundFactory/sounds/270323/), [270319](https://freesound.org/people/LittleRobotSoundFactory/sounds/270319/), [270330](https://freesound.org/people/LittleRobotSoundFactory/sounds/270330/), [270305](https://freesound.org/people/LittleRobotSoundFactory/sounds/270305/), [270304](https://freesound.org/people/LittleRobotSoundFactory/sounds/270304/) (CC-BY 3.0)
- ProjectsU012 — [341629](https://freesound.org/people/ProjectsU012/sounds/341629/), [334261](https://freesound.org/people/ProjectsU012/sounds/334261/), [360964](https://freesound.org/people/ProjectsU012/sounds/360964/), [333785](https://freesound.org/people/ProjectsU012/sounds/333785/) (CC-BY 3.0)
- TannerSound — [478262](https://freesound.org/people/TannerSound/sounds/478262/) (CC-BY 3.0)
- andersmmg — [511491](https://freesound.org/people/andersmmg/sounds/511491/) (CC-BY 3.0)
- shinephoenixstormcrow — [337050](https://freesound.org/people/shinephoenixstormcrow/sounds/337050/) (CC-BY 3.0)
- soneproject — [346425](https://freesound.org/people/soneproject/sounds/346425/) (CC-BY 3.0)
- ying16 — [353069](https://freesound.org/people/ying16/sounds/353069/) (CC-BY 3.0)
- queenoyster — [582986](https://freesound.org/people/queenoyster/sounds/582986/) (CC0)
- walkingdistance — [185197](https://freesound.org/people/walkingdistance/sounds/185197/) (CC-BY 3.0)
- melokacool — [613653](https://freesound.org/people/melokacool/sounds/613653) (CC0)

## Translation credits

Upstream GlucoseDirect was translated into 18 languages by a large community of volunteers — their work still powers DOSBTS's localization. See the [upstream README's translator list](https://github.com/creepymonster/GlucoseDirectApp/blob/main/README.md) for the full credit roll. Thank you.
