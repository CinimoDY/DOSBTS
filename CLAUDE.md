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

## Project Structure

```
App/
  App.swift                    # @main DOSBTSApp entry point
  AppState.swift               # DirectState implementation (UserDefaults-backed)
  DesignSystem/
    Colors/AmberTheme.swift    # eiDotter CGA amber color tokens
    Typography/DOSTypography.swift
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

Source: eiDotter design system. Defined in `App/DesignSystem/Colors/AmberTheme.swift`.

Key colors:
- **Primary amber:** `#ffb000` (P3 phosphor 602nm)
- **Dim amber:** `#9a5700` (secondary text)
- **Bright amber:** `#fdca9f` (highlights)
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
- Fast, snappy animations (linear, short duration)

## Development Rules

Key constraints from `docs/development-rules.md`:
- **No force unwrapping** (`!`) — use guard/let, optional chaining, nil coalescing
- **Async/await** for new code, no completion handlers
- **HealthKit is source of truth** for health data
- **Privacy by design** — no PII in logs/metadata
- **Offline-first** — core functionality works without network
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
