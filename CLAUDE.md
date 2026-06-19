# DOSBTS (formerly GlucoseDirect)

Continuous glucose monitoring (CGM) app for iOS with a DOS amber CGA aesthetic. Connects to Libre sensors via Bluetooth/NFC and displays real-time glucose data.

## Build Commands

```bash
# Build the app
xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -configuration Debug build

# Build the widget
xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSWidget -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -configuration Debug build
```

After an Xcode update: simulator builds fail until `xcodebuild -downloadPlatform iOS` runs (and a wedged CoreSimulator may need `killall -9 com.apple.CoreSimulator.CoreSimulatorService`). See `docs/solutions/build-errors/xcode-update-simulator-destinations-missing.md`.

No package manager (SPM/CocoaPods) - all dependencies are vendored or first-party.

## Architecture: Redux-like (Store/Action/Reducer/Middleware)

Based on [Daniel Bernal's Redux-like SwiftUI architecture](https://danielbernal.co/redux-like-architecture-with-swiftui-basics/).

**Core types** (all in `Library/`):
- `Store<State, Action>` — `Library/Extensions/State.swift` — Observable store, dispatches actions through reducer then middlewares
- `DirectState` protocol — `Library/DirectState.swift` — All app state properties
- `DirectAction` enum — `Library/DirectAction.swift` — All possible actions
- `DirectReducer` — `Library/DirectReducer.swift` — Pure state mutations
- `DirectStore` typealias — `Library/DirectStore.swift` — `Store<DirectState, DirectAction>`

**Data flow:**
```
View dispatches Action -> Store.dispatch() -> Reducer mutates State
                                           -> Middlewares receive (State, Action)
                                           -> Middlewares emit new Actions via Combine publishers
```

**Middlewares** are defined in `App/Modules/` — each module file contains middleware functions (not classes). They return `AnyPublisher<DirectAction, DirectError>?`. There is no `Middleware` folder; look for `func ...Middleware` patterns.

**State persistence:** `AppState` (`App/AppState.swift`) implements `DirectState` and persists most properties to `UserDefaults`.

**Architecture gotchas:**
- **Reducer runs BEFORE middlewares** — `Store.dispatch()` calls `reducer(&state, action)` first, then passes the *new* state to middlewares. Don't guard on state that the reducer just changed for the same action flow.
- **`fileSystemSynchronized` Xcode project** — new Swift files under `App/`, `Library/`, or `Widgets/` are auto-picked up; no manual pbxproj edits needed. Per-target exclusions live in `PBXFileSystemSynchronizedBuildFileExceptionSet` (currently excludes widget resources + `Extensions/Float.swift` from the widget target, and `Info.plist` from both app/widget auto-inclusion). Adding a new test file requires an explicit entry in `DOSBTSTests` group + `PBXSourcesBuildPhase` — the tests are NOT auto-synced.
- **Two middleware arrays** in `App.swift` (device + simulator) — both must be updated when adding middleware
- **Deployment target is iOS 26.0** — bumped from 15.0 in DMNC-769 to match DOOMBTS and adopt iOS 17+ APIs (new `onChange(of:_:)` two-arg form, etc.). Legacy `if #available(iOS 15.x/16.x/17.x, *)` guards were swept in DMNC-776/777/778 (PR #23) — none remain.
- **`UIApplication.shared` is `NS_EXTENSION_UNAVAILABLE`** — code using it must live under `App/`, never shared `Library/`. See `App/Extensions/UIScreen.swift` for the iOS 26 scene-lookup pattern + `docs/solutions/best-practices/ios-26-uiscreen-main-migration-20260422.md` for the full migration subtleties.
- **Deploy to TestFlight:** `./deploy.sh` (uses ASC API key). `ExportOptions.plist` uses automatic signing. **`deploy.sh` does NOT auto-bump** — manually change `CURRENT_PROJECT_VERSION` in pbxproj (4 occurrences) and promote `[Unreleased]` → `[Build N]` in `CHANGELOG.md` (see CHANGELOG section below) **before** running the script. If a connected iPhone is passcode-locked, archive will fail — unlock or disconnect it. Provisioning profiles are per-macOS-account; if deploying from a new account, archive once from Xcode first to generate them.
- **SwiftUI nested sheets are unreliable** — never present a `.sheet` from within a view that is itself presented as a `.sheet`. Use `NavigationLink` (push) instead. This applies to all iOS versions, not just iOS 15. See `docs/solutions/ui-bugs/swiftui-nested-sheets-present-wrong-view-20260316.md`.
- **Cross-middleware listening** — multiple middlewares can handle the same action (e.g., `.addMealEntry` triggers both `mealEntryStoreMiddleware` and `favoriteFoodStoreMiddleware`). Comment these cross-dependencies for maintainability.
- **Data load guards** — all DataStore middlewares guard `state.appState == .active` before loading. The `.active` state is set in `ContentView.onAppear`. If adding new data store middlewares, follow this pattern: handle `.setAppState(.active)` to trigger initial load, and guard `.active` in the load action handler. See `docs/solutions/logic-errors/appstate-inactive-blocks-data-loading-20260317.md`.
- **Single presentation root: `SheetCoordinator`** — ALL sheets (insulin, meal, blood glucose, treatment modal/recheck, filtered entry, chart-marker overlay/edit) present through `App/Views/SheetCoordinator.swift`, hosted by ContentView's one `.sheet(item:)` (content in `RootSheetContent.swift`). Safety presents (treatment modal/recheck) PREEMPT the active sheet and dispatch `.selectView(overview)`; ordinary presents pend; duplicates (same case id) no-op; the `stillLow` double-flag resolves via `SheetCoordinator.treatmentPresent(...)` (recheck wins). Never add a local `.sheet` for these flows — that recreates the sibling-sheet bug class. Use `dismissThenPresent` for dismiss-then-present sequencing (not `asyncAfter`).
- **Settings is a drill-down hub** — `SettingsView` is 6 NavigationLink category rows; section views (e.g. `AlarmSettingsView`) are bare-`Section` providers composed into category `List`s under `App/Views/Settings/`. `SettingsConnectionsView` doubles as the Integrations index. Dependent controls dim (`.disabled` + `.opacity`) instead of hiding; capability/consent-gated sections (AI, Bellman, Calibration) stay conditional — DMNC-794.
- **Overview layout order** — hero glucose → sensor line → treatment banner (if active) → chart (with report type selector). The INSULIN/MEAL buttons are NOT on Overview anymore — they live in the persistent bottom bar (below). ChartView has a `@State selectedReportType` enum switching between GLUCOSE (chart), TIME IN RANGE (TAR/TIR/TBR bars), and STATISTICS (AVG/SD/CV/GMI). The chart content is extracted into a `GlucoseChartContent` computed property; chart height derives from available space via `chartHeight(available:)` — never size it from `UIScreen` (see docs/solutions/ui-bugs/swiftui-vstack-overflow-sinks-safeareainset.md).
- **Persistent bar + strip (all tabs)** — `GlucoseStatusBar` (INSULIN/MEAL ghost buttons) mounts per tab via `safeAreaInset(edge: .bottom)`, NOT `tabViewBottomAccessory` (its glass capsule fights DOS theming — docs/solutions/best-practices/ios-26-liquid-glass-theming-gotchas.md). MEAL routes `treatmentCycleActive ? .filteredFoodEntry : .meal` (R8). `GlucoseTopBar` is a slim glucose strip above the page title on Log/Settings/Digest; `GlucoseFramedTab` wraps NavigationStack tabs with both. Staleness tiers shared via `Library/Content/GlucoseStaleness.swift` (5 min amber / 15 min red) — hero and strip must never diverge.
- **CGA root defaults + nav titles** — App.swift applies `.tint(amber)`, `.foregroundStyle(amber)`, `.fontDesign(.monospaced)` at the root: unstyled text renders amber mono ("no real white"). iOS 26 ignores `UINavigationBar.appearance()` title attributes — style titles with `dosNavigationTitle` (principal toolbar item, `App/DesignSystem/Modifiers/DOSModifiers.swift`), never `.navigationTitle` alone. `navigationDestination` is silently IGNORED inside legacy `NavigationView` — use `NavigationStack` (remaining sweep: DMNC-1027).
- **Food analysis has three input paths** — `analyzeFood(imageData:)` for photos, `analyzeFoodText(query:history:)` for NL text (with optional multi-turn follow-up), and `analyzeFoodBarcode(code:)` for barcode scanning (Open Food Facts). All three share `foodAnalysisResult/Loading/Error` state and reuse `FoodPhotoAnalysisView` as the staging plate. Photo and text paths require `aiConsentFoodPhoto` consent gate; barcode path does NOT (OFF is free). Text path supports conversational follow-up (up to 3 rounds) when confidence is low — follow-up state lives in `@State` (not Redux), staging plate stays visible during follow-up loading.
- **Treatment workflow (Rule of 15)** — `TreatmentCycleMiddleware` orchestrates guided hypo treatment: alarm fires → `.showTreatmentPrompt` → user logs treatment → 15-min countdown → recheck glucose → stabilised or treat again. Two UI surfaces: UNNotificationAction buttons (background/lock screen) and TreatmentModalView (foreground). Alarm suppression during countdown (sound-only, banners continue) with critical-low safety floor (`alarmLow - 15 mg/dL` breaks through). Treatment cycle state persists to UserDefaults (survives app kill). TreatmentEvent stored in GRDB (write-only V1) for future absorption analysis. `treatmentCycleSnoozeUntil` is separate from `alarmSnoozeUntil` — GlucoseNotification checks both. Configurable wait time via `hypoTreatmentWaitMinutes` (default 15). TreatmentBannerView has 4 states: countdown, rechecking, stale data, recovered (auto-dismiss 5s).
- **Predictive low alarm** — GlucoseNotification middleware extrapolates glucose trajectory using smoothed `minuteChange` (avg of 3 readings) projected 20 min forward. Fires "Trending Low" notification with `predictiveLowAlarm` UNNotificationCategory ("EAT NOW" button) when predicted to cross `alarmLow`. CRITICAL: does NOT trigger autosnooze — actual low alarm fires independently. Does NOT fire when `treatmentCycleActive` (prevents snooze cascade). Once-per-episode dedup via `predictiveLowAlarmFired` flag, cleared at `alarmLow + 10` or on actual low. Chart shows dashed projection line with red cross marker at predicted threshold crossing. Toggle: `showPredictiveLowAlarm` (default on).
- **Day/night alarm profiles** — Two threshold + volume profiles switched on a fixed user-configured time window (default 22:00→07:00, configurable in Settings → Alarms & Alerts). `state.alarmHigh / alarmLow / alarmVolume` on `DirectState` are `{ get }`-only **computed accessors** that resolve via `state.activeAlarmProfile`; the actual storage lives in six per-profile + four schedule properties (`dayAlarmHigh`, `nightAlarmHigh`, `nightStartHour`, etc.). Day setters dual-write to legacy `alarmHigh / alarmLow / alarmVolume` UserDefaults keys for safe rollback to a pre-feature build; night setters single-write. Migration in `AppState.init` is once-per-install (gate: `hasMigratedAlarmProfiles`) and copies legacy values into both profiles or seeds defaults (180/80/0.2). Treatment cycle, snooze, predictive low, and critical-low breakthrough (`isCriticalLow` helper in `Library/Content/AlarmProfile.swift`) all read the active profile transparently — no cycle pinning. **Accepted boundary-flip behavior:** a hypo cycle started under day rules can declare "recovered" against a more permissive night threshold if the boundary crosses mid-cycle; the predictive-low flag's clear-zone (`alarmLow + 10`) similarly flips. Pinned in `BoundaryFlipBehaviorTests`. The Settings warning rows for "night more permissive than day" discourage the user-config side of this; the deeper threshold-locking refactor is tracked as DMNC-895 for if/when a real-world user reports the failure mode. Sensor end-of-life warnings use `max(dayAlarmVolume, nightAlarmVolume)` so a silenced night never suppresses an overnight failure. Cross-target sync: `AppGroupSharing.writeAlarmProfileData(state:)` mirrors schedule + per-profile thresholds to `UserDefaults.shared` on `.startup`, `.addSensorGlucose`, and each non-volume per-profile setter (volume excluded — slider drag would burn the ActivityKit push budget without user-visible benefit). Live Activity ContentState carries 8 optional schedule + per-profile fields plus the legacy day-anchored `alarmLow / alarmHigh` for pre-upgrade in-flight activities. **Render-time resolution gotcha:** Home Screen widget pre-resolves entries at `getTimeline` build time, so a single-entry timeline can show stale thresholds for up to the reload window past a boundary; `GlucoseUpdateProvider` emits a second timeline entry at the next boundary via `nextAlarmProfileBoundary(...)`. Live Activity is naturally correct via `effectiveAlarmThresholds(at:)` called from the view body. See `docs/solutions/best-practices/widgetkit-timeline-time-of-day-boundary-entries-20260503.md`.
- **Chart markers** — Meal/insulin entries grouped by 15-min `timegroup`; rendering lives in the **Event marker lane** (below), not in-chart. Tapping a group opens detail sheet with individual items (swipe-to-delete, tap-to-edit). Meal edit sheet has Delete button (`deleteCallback`). Insulin tap shows `confirmationDialog` with Delete option. (The legacy `ConsolidatedMarkerGroup.summaryLabel`/`dominantType`/`totalCarbs` helpers from the old in-chart diamond/circle annotation are now **dead code** — tracked for removal in DMNC-1146.)
- **Stale data indicator** — GlucoseView shows "X MIN AGO" warning when latest reading is >5 min old. Amber text for 5-14 min, red for 15+. Prevents dosing decisions on silently stale data.
- **Tight-control streak celebration** — `tightControlStreakMiddleware` (`App/Modules/TightControlStreak/`) watches `.addSensorGlucose`/`.setSensorGlucoseValues` and a **pure** `TightControlStreakDetector` (band 80–120 mg/dL, 2h continuous, gap = `max(2×interval, 12min)`, hysteresis re-arm = 2 readings beyond ±5 mg/dL) to fire a one-time "TIGHT CONTROL" celebration. A persisted dedup marker (last-celebrated streak start) makes launch-replay idempotent — no double-fire. Middleware is pure (emits a `withFeedback` flag); the `TightControlToast` controller in ContentView owns sound (`achievement.aiff`) / haptic / VoiceOver, gated to visual-only during night-profile hours and respecting Reduce Motion. Deferred toast: streaks earned while backgrounded present consolidated ("×N") on next `.setAppState(.active)` (the SOLE pending-drain trigger; `.addSensorGlucose`/`.setSensorGlucoseValues` detect-and-present). Lifetime count on the STATISTICS card; Settings → Alarms & Alerts toggle (`showCelebrations`, default on). Registered in BOTH App.swift arrays. DMNC-772 (Build 105).
- **Insulin-on-Board (IOB)** — `IOBCalculator.swift` implements OpenAPS oref0 Maksimovic exponential decay model. `InsulinPreset` enum (rapidActing peak 75m/DIA 6h, ultraRapid peak 55m/DIA 6h) with separate basal DIA (2-24h). IOB computed on-read from `iobDeliveries` (DIA-window filtered, loaded by `IOBMiddleware`). Hero display (GlucoseView) with 60s refresh timer, split display toggle (M=meal/snack, B=basal+corr). Chart AreaMark overlay (cgaCyan/amberDark). Stacking warning in AddInsulinView (amber, correction bolus only, reactive to picker). IOB on TreatmentBannerView (countdown/rechecking states, second line). `InsulinSettingsView` with preset picker, basal DIA stepper, split toggle. Future deliveries excluded from IOB (not yet delivered). Zero threshold: 0.05U.
- **Meal impact overlay** — Tap single meal markers to see 2-hour post-meal glucose delta (color-coded green/amber/red), confounder detection (correction bolus, exercise, stacked meal), and PersonalFood rolling glycemic average. `MealImpactStore` middleware computes impacts on dual triggers (retroactive on app activation + real-time on new glucose readings). `analysisSessionId` links AI-analyzed meals to PersonalFood glycemic scores.
- **Event marker lane** — Dedicated 60pt lane above the glucose chart replacing in-chart meal/insulin annotations. Icons per type (`apple.logo`/`AppleIcon` meals, `syringe.fill` bolus + correction, `syringe` outline basal, `figure.run` exercise). Overlap-based consolidation (`consolidateByOverlap`) merges chips whose estimated widths would collide. Each chip stacks **at most 3 rows in the locked order insulin → meal → exercise**: all insulin sub-types (meal/snack bolus, correction, basal) collapse into a **single insulin row** as colored segments, each keeping its color + suffix (`5U` bolus / `2Uc` correction / `10Ub` basal) — this guarantees the ≤3-row / 60pt budget and preserves the correction distinction (DMNC-715). Scored meals get a `★` prefix. Row-building is extracted into a testable `ConsolidatedMarkerGroup.chipRows(isScored:)` (`Library/Content/EventMarker.swift`); `MarkerChipRowTests` pins the 3-row invariant + segment labels. `EventMarkerLaneView` is a self-contained view receiving pre-computed `ConsolidatedMarkerGroup` data and tap callbacks. Tap meal → meal impact overlay; tap insulin → confirmation dialog; tap group → expanded panel.
- **Daily Digest tab** — Fourth tab (Overview > Lists > Settings > Digest) showing daily glucose summary. `DailyDigestMiddleware` computes stats from raw GRDB data (glucose, meals, insulin, exercise) and generates AI insight via Claude Haiku with full context + 7-day cross-day history. `DailyDigest` model persisted to GRDB for history browsing. Date navigation for past days. Today always recomputes (no stale cache). Separate `aiConsentDailyDigest` consent toggle. Events loaded into `dailyDigestEvents` state for timeline display. `DigestView` has date nav bar, 2x3 stats grid (color-coded), AI insight card (cyan border), and chronological event timeline. The insight is structured JSON (`Library/Content/DigestInsight.swift`: headline/grade/facts/tips/cheer) stored in the existing `aiInsight` string column and rendered as a DOS infographic with a staged reveal; unparseable/legacy rows fall back to plain-text rendering.
- **GRDB deadlock: never write inside asyncRead** — `DatabaseQueue` serializes all access. Calling `dbQueue.write` from inside a `dbQueue.asyncRead` callback deadlocks (read holds queue, write waits for queue). Always return data via the Future promise and do writes separately. See `docs/solutions/logic-errors/grdb-write-inside-asyncread-deadlock-20260420.md`.
- **Combine Future-to-async bridge: guard double-resume** — When bridging a `Future` to async/await via `withCheckedThrowingContinuation`, the `receiveValue` and `receiveCompletion` callbacks both fire (Future emits one value then completes). Must use a `resumed` flag to call `continuation.resume` exactly once. See `docs/solutions/logic-errors/combine-future-async-bridge-double-resume-20260420.md`.
- **Widget target has separate design system** — `Widgets/WidgetDesignSystem.swift` mirrors AmberTheme/DOSTypography colors and fonts for the widget extension (can't import app module). Pure logic types (`SparklineBuilder`, `DataStaleness`) live in `Library/Content/SparklineBuilder.swift` (both targets) for testability. Widget-specific color properties are extensions in the widget file.
- **Widget shared data via App Group** — `AppGroupSharing` middleware writes TIR, IOB, last meal, and sparkline to `UserDefaults.shared` (App Group suite) on each glucose update. IOB is pre-computed (read from `sharedIOB`), not recomputed in the sharing middleware. Widget data writes dispatch to background queue.
- **Live Activity data flows through ContentState** — never read `UserDefaults.shared` directly in Live Activity views. All data (glucose, IOB, sparkline) must pass through `SensorGlucoseActivityAttributes.ContentState` via `ActivityGlucoseService.getStatus()`. Direct UserDefaults reads bypass ActivityKit's sync mechanism and serve stale data on lock screen/rehydration.
- **Snapshot testing** — XCTest target `DOSBTSTests` with 350+ tests covering SheetCoordinator present/preempt semantics + treatment decision matrix, GlucoseStatusBar R7b state mapping + R8 routing, GlucoseStaleness tiers, MealItemRow display model, DigestInsight parsing, caption-contrast pins, design-token + animation-token value pins (`DesignTokenPinTests`/`AnimationTokensTests`), event-marker chip-row 3-row-invariant layout (`MarkerChipRowTests`), IOB calculation engine, IOB reducer state, treatment cycle lifecycle, predictive alarm flags, alarm snooze auto-clear, treatment prompt state, MealImpact model, MealImpact reducer, delta thresholds, rolling average math, analysisSessionId linkage, PersonalFood glycemic fields, DailyDigest model/reducer, GlucoseStatistics computed properties, SensorGlucose clamping/minuteChange, SensorTrend slope classification, CustomCalibration regression, Sensor lifecycle, alarm thresholds, connection state, and glucose unit switching. Swift Testing framework (`@Test`, `#expect`). Run with Cmd+U on simulator. Tests are UserDefaults-isolated: `AppState(defaults:)` accepts an injected store, and `makeTestDefaults()` (DirectReducerTests.swift) hands every test a fresh suite — never construct `AppState()` bare in tests or pollution flakes return.

## Project Structure

```
App/
  App.swift                    # @main DOSBTSApp entry point
  AppState.swift               # DirectState implementation (UserDefaults-backed)
  DesignSystem/
    Components/DOSButtonStyle.swift  # App-only button styles
    Modifiers/DOSModifiers.swift     # App-only view modifiers
  Modules/                     # Feature middlewares
    SensorConnector/           # BLE/NFC sensor connections
      SensorConnector.swift    # Main middleware + glucose filtering
      SensorBluetoothConnection.swift
      LibreConnection/         # Libre 2, LibreLink, LibreLinkUp
      BubbleConnection/        # Bubble transmitter
      VirtualConnection/       # Simulator testing
    DataStore/                 # GRDB-based persistence
    Nightscout/                # Nightscout upload
    AppleExport/               # HealthKit & Calendar export
    GlucoseNotification/       # Glucose alerts
    ConnectionNotification/
    ExpiringNotification/
    BellmanAlarm/
    ReadAloud/
    WidgetCenter/
    ScreenLock/
    TreatmentCycle/            # Hypo treatment workflow (Rule of 15)
    Claude/                    # AI food photo analysis (Claude Haiku)
    IOB/                       # Insulin-on-Board decay model middleware
    MealImpact/                # Meal impact overlay computation middleware
    DailyDigest/               # Daily digest stats + AI insight middleware
    Log/
    Debug/
  Views/
    OverviewView.swift         # Main glucose display
    DigestView.swift           # Daily digest tab (stats grid, AI card, timeline)
    SettingsView.swift         # Settings hub — 6 category rows, each pushes a category screen
    CalibrationsView.swift
    ListsView.swift
    Overview/                  # Chart, sensor, connection subviews
    Settings/                  # Category screens (Alarms & Alerts, Glucose & Display, Insulin, Sensor & Connection, Integrations, System & About) + section-provider views
    SharedViews/               # Reusable components
    AddViews/                  # Meal entry, photo analysis, insulin, blood glucose, calibration
Widgets/
  Widgets.swift                  # @main WidgetBundle
  WidgetDesignSystem.swift       # Widget-local colors, fonts, phosphor glow
  GlucoseWidget.swift            # Home screen (small/medium/large) + lock screen widgets
  GlucoseActivityWidget.swift    # Live Activity + Dynamic Island
  SensorWidget.swift             # Lock screen sensor lifetime gauge
  TransmitterWidget.swift        # Lock screen transmitter battery gauge
Library/
  Extensions/State.swift       # Store class, Reducer/Middleware typealiases
  DirectState.swift            # State protocol
  DirectAction.swift           # Action enum
  DirectReducer.swift          # Reducer function
  DirectStore.swift            # DirectStore typealias
  DirectNotifications.swift
  Content/                     # Domain models (Sensor, SensorGlucose, BloodGlucose, etc.)
  DesignSystem/                # Shared design tokens (both targets)
    AmberTheme.swift           # CGA amber color tokens
    DOSTypography.swift        # SF Mono font styles
    DOSSpacing.swift           # 8px grid spacing
  Extensions/                  # Swift type extensions
```

## Sensor Connection Protocol

All sensor connections implement `SensorConnectionProtocol` (`Library/Content/SensorConnection.swift`):
```swift
protocol SensorConnectionProtocol {
    var subject: PassthroughSubject<DirectAction, DirectError>? { get }
    func pairConnection()
    func connectConnection(sensor: Sensor, sensorInterval: Int)
    func disconnectConnection()
    func getConfiguration(sensor: Sensor) -> [SensorConnectionConfigurationOption]
}
```

Connections emit `DirectAction`s through a `PassthroughSubject`. Available connections:
- `Libre2Connection` — Direct Libre 2 via NFC+BLE
- `LibreLinkConnection` — LibreLink companion
- `LibreLinkUpConnection` — LibreLinkUp cloud API
- `BubbleConnection` — Bubble transmitter via BLE
- `VirtualConnection` — Simulated data for testing

## Design System: DOS Amber CGA

Source: eiDotter design system. Shared tokens in `Library/DesignSystem/` (`AmberTheme.swift`, `DOSTypography.swift`, `DOSSpacing.swift`). App-only components in `App/DesignSystem/` (`Components/DOSButtonStyle.swift`, `Modifiers/DOSModifiers.swift`).

Key colors:
- **Primary amber:** `#ffb000` (P3 phosphor 602nm)
- **Dim amber:** `#9a5700` (secondary text) → `AmberTheme.amberDark`
- **Bright amber:** `#fdca9f` (highlights) → `AmberTheme.amberLight` (NOT amberBright)
- **Background:** `#000000` (pure black)
- **Success/Low:** `#55ff55` (CGA green) → `AmberTheme.cgaGreen`
- **Error/High:** `#ff5555` (CGA red) → `AmberTheme.cgaRed`
- **Warning:** `#ffff55` (CGA yellow) — no dedicated property yet
- **Info:** `#55ffff` (CGA cyan) → `AmberTheme.cgaCyan`

Typography API (`DOSTypography`): `displayMedium` (28pt bold), `bodyLarge` (20pt), `body` (17pt), `bodySmall` (15pt), `caption` (12pt), `button` (17pt semibold), `tabBar` (10pt), `glucoseHero` (60pt bold), `mono(size:weight:)`. No `headline` or `title` members.

Rules:
- All text uses monospace fonts (`DOSTypography`)
- Sharp corners preferred (DOS aesthetic)
- Dark theme only (`.preferredColorScheme(.dark)`)
- 8px grid spacing
- SF Symbols have inconsistent intrinsic sizes — use `.frame(height:)` on icons when pixel-perfect alignment matters
- Fast, snappy animations (linear, short duration)

**Prototype-Driven Design Workflow** (provisional — full docs in `docs/design-system.md`):
- **Dense/new screens**: use a Figma frame as the exact design source-of-truth. Frame URL → live MCP read (`mcp__claude_ai_Figma__get_design_context`) → implement → verify by screenshot.
- **Small/incremental changes**: prose description is fine — no frame required.
- **No-MCP fallback**: implement from the committed PNG snapshot + companion spec in `docs/design-frames/` (see `docs/design-frames/README.md`).
- **Token consumption flow**: PORT (existing `AmberTheme` token) → SKIP (system-handled) → EVALUATE (new: add to `AmberTheme.swift`, update `DesignTokenPinTests.swift`, document here). Never copy raw hex.
- **Platform constraints** (check before implementing any frame): `dosNavigationTitle` for nav bar titles; `safeAreaInset(edge: .bottom)` for persistent bars; no nested `.sheet` inside a sheet; no real white; `DOSTypography` members only; `NavigationStack` not `NavigationView`.

## Adding New State Properties

**For UserDefaults-backed settings** (toggles, preferences), add in 4 files:
1. `Library/DirectState.swift` — protocol declaration
2. `App/AppState.swift` — property with `didSet` + init from UserDefaults
3. `Library/Extensions/UserDefaults.swift` — `Keys` enum case + computed property
4. `Library/DirectReducer.swift` — reducer case

**For GRDB-backed data** (arrays loaded from database like `mealEntryValues`, `favoriteFoodValues`), add in 3 files — skip UserDefaults:
1. `Library/DirectState.swift` — protocol declaration
2. `App/AppState.swift` — property with default `= []` (no `didSet`, no UserDefaults)
3. `Library/DirectReducer.swift` — reducer case for the `set` action

Don't forget `Library/DirectAction.swift` if a new action is needed.

## Adding New Files to Xcode Project

The project uses Xcode's `fileSystemSynchronized` build system (DMNC-768). New `.swift` files placed anywhere under `App/`, `Library/`, or `Widgets/` are picked up automatically — no pbxproj edits needed.

Exceptions:
- **Tests** are NOT auto-synced. New files under `DOSBTSTests/` must be added to the `DOSBTSTests` group and `PBXSourcesBuildPhase` in `project.pbxproj` manually.
- **Widget-only exclusions.** The `DOSBTSWidget` target excludes `Library/Extensions/Float.swift` and all files in `Library/Resources/` (audio + `sensor.png`). If you add a new file under `Library/Resources/` that the widget should NOT include, add it to `E8217F012F97F9B800ACCE52 /* PBXFileSystemSynchronizedBuildFileExceptionSet */` in `project.pbxproj`.
- **Info.plist** is excluded from auto-inclusion (uses explicit `INFOPLIST_FILE` build setting).

## Adding GRDB Table Columns

Use `DatabaseMigrator` in the store's `create...Table()` method (see `SensorGlucoseStore.swift` for pattern):
```swift
var migrator = DatabaseMigrator()
migrator.registerMigration("description") { db in
    try db.alter(table: MyModel.Table) { t in
        t.add(column: MyModel.Columns.newColumn.name, .double)
    }
}
try migrator.migrate(dbQueue)
```
Also add the column to the `Columns` enum in `DataStore.swift`.

## Development Rules

Key constraints from `docs/development-rules.md`:
- **No force unwrapping** (`!`) — use guard/let, optional chaining, nil coalescing, or `URL(staticString:)` (`Library/Extensions/URL.swift`) for static URL literals
- **Async/await** for new code, no completion handlers
- **HealthKit is source of truth** for health data
- **Privacy by design** — no PII in logs/metadata
- **Offline-first** — core functionality works without network
- **No secrets in Redux actions** — never put API keys or tokens in action associated values; use Keychain as a side channel
- Conventional commits: `type(scope): subject` (feat, fix, docs, style, refactor, test, chore)

## CHANGELOG

- Every user-visible change goes under `## [Unreleased]` in `CHANGELOG.md` as part of the same PR that ships the change. "User-visible" = ships in the app binary and a user can observe it (new feature, bug fix, copy change, visible layout change). Internal-only changes (refactors, tooling, CI, compound learnings, developer docs) don't need an entry.
- When bumping `CURRENT_PROJECT_VERSION` for TestFlight, promote the `[Unreleased]` block to `## [Build N] — YYYY-MM-DD` and add a new empty `[Unreleased]` above it.
- Date is the TestFlight upload date, not the commit date. Use `git log` or App Store Connect to verify if in doubt.
- Group entries under `Added` / `Changed` / `Fixed` / `Removed` per [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Append ` — DMNC-NNN, PR #NN` when the entry has a tracking issue and/or PR; otherwise just the description.
- **Deploy-time cross-check:** before promoting `[Unreleased]`, list PRs merged since the last `chore: bump build` commit and backfill any missing user-visible entries (PR #55/DMNC-1039 slipped through and was caught this way at Build 102).
- **Split-cycle rule:** if a feature merges before the `CURRENT_PROJECT_VERSION` bump but ships only after the next bump, move its entry to the correct `[Build N]` at promotion time.
- **Yanked builds:** if a TestFlight build is withdrawn, leave its `[Build N]` block in place and add a `**Yanked.**` header line with the reason. Promote the next `CURRENT_PROJECT_VERSION` bump as normal.

## Docs

Additional documentation in `docs/`:
- `architecture.md` — System architecture
- `design-system.md` — Full design system spec
- `requirements.md` — Feature requirements
- `technology-stack.md` — Tech stack details
- `project-structure.md` — Directory layout
- `ui-mockups.md` — UI mockups
- `apple-watch-architecture.md` — Watch extension plans
- `solutions/` — Documented solutions to past problems (bugs, best practices, workflow patterns), organized by category with YAML frontmatter (`module`, `tags`, `problem_type`). Relevant when implementing or debugging in documented areas.
