# DMNC-1225: Retire Pre-Existing Build Warnings

**Date**: 2026-07-02  
**Branch**: claude/dmnc-1225  
**Issue**: [DMNC-1225](https://linear.app/lizomorf/issue/DMNC-1225/chore-retire-pre-existing-build-warnings-onchange-deprecation-badge)

## Summary

Three pre-existing compiler warnings surfaced in the Build 118 archive log. All cosmetic — no user-visible change, no behaviour impact. Retired them now that the deployment target is iOS 26 and the modern APIs are available.

## Changes

### 1. `onChange(of:perform:)` deprecation — `Library/DesignSystem/DOSTypography.swift`

Two `ViewModifier` bodies (`DOSPowerOnModifier`, `DOSPowerOffModifier`) used the deprecated single-argument `onChange` closure form introduced before iOS 17:

```swift
// Before (deprecated iOS 17)
.onChange(of: isActive) { active in … }

// After (two-parameter form)
.onChange(of: isActive) { _, active in … }
```

The old value is not needed in either closure, so `_` discards it. Consistent with the sweep done in DMNC-776/777/778 that covered the rest of the codebase.

### 2. Badge API — `App/Modules/GlucoseNotification/GlucoseNotification.swift`

`UIApplication.shared.applicationIconBadgeNumber = 0` was deprecated in iOS 17 in favour of the `UNUserNotificationCenter` API:

```swift
// Before (deprecated iOS 17)
UIApplication.shared.applicationIconBadgeNumber = 0

// After
UNUserNotificationCenter.current().setBadgeCount(0, withCompletionHandler: nil)
```

`clear()` is not async, so the completion-handler-with-nil form is the correct fit — fire-and-forget, same behaviour.

### 3. Sendable capture — `App/Modules/SensorConnector/LibreConnection/LibreLinkUpConnection.swift`

A `Task { }` closure in `connectConnection` captured `self` (a `LibreLinkUpConnection`) in a `@Sendable` context. The compiler warned because `LibreLinkUpConnection` did not conform to `Sendable`.

Fix: add `@unchecked Sendable` to the class declaration:

```swift
// Before
class LibreLinkUpConnection: SensorBluetoothConnection, IsSensor {

// After
class LibreLinkUpConnection: SensorBluetoothConnection, IsSensor, @unchecked Sendable {
```

`@unchecked` is appropriate here: the class already serialises all BLE operations through `managerQueue` (a dedicated `DispatchQueue`), and its parent `SensorBluetoothConnection` is `NSObject`-based where the same pattern holds. Full `Sendable` migration would require refactoring all mutable properties and is out of scope.

## Verification

✅ **Build**: Three files recompiled clean, zero warnings from the affected lines  
✅ **No test changes required** — purely API surface, no logic change  

## Notes

- No CHANGELOG entry required — internal-only, not user-visible.
- The `UIKit` / `AmberTheme` SourceKit false-positive diagnostics in the IDE are pre-existing cross-target resolution issues unrelated to these changes.
