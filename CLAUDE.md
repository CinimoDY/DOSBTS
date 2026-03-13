# DOSBTS (formerly GlucoseDirect)

Continuous glucose monitoring (CGM) app for iOS with a DOS amber CGA aesthetic. Connects to Libre sensors via Bluetooth/NFC and displays real-time glucose data.

## Build Commands

```bash
# Build the app
xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSApp -sdk iphonesimulator -configuration Debug build

# Build the widget
xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSWidget -sdk iphonesimulator -configuration Debug build
```

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

**Middlewares** are defined in `App/Modules/` — each module file contains middleware functions (not classes). They return `AnyPublisher<DirectAction, DirectError>?`. There is no `Middleware` folder; look for `func ...Middleware` or `func ...Middelware` (note: typo is in the codebase) patterns.

**State persistence:** `AppState` (`App/AppState.swift`) implements `DirectState` and persists most properties to `UserDefaults`.

**Architecture gotchas:**
- **Reducer runs BEFORE middlewares** — `Store.dispatch()` calls `reducer(&state, action)` first, then passes the *new* state to middlewares. Don't guard on state that the reducer just changed for the same action flow.
- **Traditional Xcode project** (NOT `fileSystemSynchronized`) — new files require manual `pbxproj` entries
- **Two middleware arrays** in `App.swift` (device + simulator) — both must be updated when adding middleware
- **Deployment target is iOS 15.0** — watch for iOS 16+/17+ only APIs (e.g. `PhotosPicker` needs `@available` guard + fallback)
- **Deploy to TestFlight:** `./deploy.sh` (uses ASC API key). `ExportOptions.plist` uses automatic signing. Bump `CURRENT_PROJECT_VERSION` in pbxproj before each deploy.

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
    Claude/                    # AI food photo analysis (Claude Haiku)
    Log/
    Debug/
  Views/
    OverviewView.swift         # Main glucose display
    SettingsView.swift
    CalibrationsView.swift
    ListsView.swift
    Overview/                  # Chart, sensor, connection subviews
    Settings/                  # Individual settings screens
    SharedViews/               # Reusable components
    AddViews/                  # Blood glucose, insulin, calibration entry
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
- **Success/Low:** `#55ff55` (CGA green)
- **Error/High:** `#ff5555` (CGA red)
- **Warning:** `#ffff55` (CGA yellow)
- **Info:** `#55ffff` (CGA cyan)

Rules:
- All text uses monospace fonts (`DOSTypography`)
- Sharp corners preferred (DOS aesthetic)
- Dark theme only (`.preferredColorScheme(.dark)`)
- 8px grid spacing
- SF Symbols have inconsistent intrinsic sizes — use `.frame(height:)` on icons when pixel-perfect alignment matters
- Fast, snappy animations (linear, short duration)

## Adding New State Properties

New state must be added in 4 files:
1. `Library/DirectState.swift` — protocol declaration
2. `App/AppState.swift` — property with `didSet` + init from UserDefaults
3. `Library/Extensions/UserDefaults.swift` — `Keys` enum case + computed property
4. `Library/DirectReducer.swift` — reducer case

Don't forget `Library/DirectAction.swift` if a new action is needed.

## Adding New Files to Xcode Project

No SPM/xcodeproj tooling — new `.swift` files must be added to `DOSBTS.xcodeproj/project.pbxproj` manually in 4 sections:
- PBXBuildFile, PBXFileReference, PBXGroup (parent folder's children), PBXSourcesBuildPhase
- Use unique hex IDs following existing patterns

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
- **No force unwrapping** (`!`) — use guard/let, optional chaining, nil coalescing
- **Async/await** for new code, no completion handlers
- **HealthKit is source of truth** for health data
- **Privacy by design** — no PII in logs/metadata
- **Offline-first** — core functionality works without network
- **No secrets in Redux actions** — never put API keys or tokens in action associated values; use Keychain as a side channel
- Conventional commits: `type(scope): subject` (feat, fix, docs, style, refactor, test, chore)

## Docs

Additional documentation in `docs/`:
- `architecture.md` — System architecture
- `design-system.md` — Full design system spec
- `requirements.md` — Feature requirements
- `technology-stack.md` — Tech stack details
- `project-structure.md` — Directory layout
- `ui-mockups.md` — UI mockups
- `apple-watch-architecture.md` — Watch extension plans
