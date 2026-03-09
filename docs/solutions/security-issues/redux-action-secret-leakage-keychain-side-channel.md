---
title: "Secure API Key Management in Redux Architecture via iOS Keychain"
category: security-issues
tags:
  - redux
  - keychain
  - api-keys
  - secrets-management
  - middleware
  - swiftui
  - ios
module: App/Modules/Claude
symptom: "API key passed as associated value in Redux action, causing secrets to appear in state logs and action descriptions"
root_cause: "Treating secrets like regular state in a Redux pattern where all actions flow through logging middleware"
date: 2026-03-09
related_issues:
  - DMNC-427
---

# Secure API Key Management in Redux Architecture via iOS Keychain

## Problem

In a Redux-like SwiftUI architecture where all actions flow through a central store and are logged by middleware, passing secrets (API keys) as associated values on action enum cases causes them to appear in plain text in:

- File-based logs (exportable via "Send Logs")
- State debugging output
- Crash reporting that captures state snapshots

The `Log.swift` middleware logs all action descriptions by default. While some actions (`nightscoutURL`, `nightscoutSecret`) were explicitly excluded from logging, this exclusion-list pattern is fragile -- any new secret-bearing action must be manually added or it leaks.

## Root Cause

The Redux pattern's strength (all state changes are observable and traceable) becomes a liability when secrets are embedded in the action stream. The action enum's `CustomStringConvertible` conformance means `String(describing: action)` includes all associated values.

## Solution: Keychain-First, Reference-Only Actions

Separate secret storage from action dispatch. Secrets are written to the Keychain *before* any action is dispatched, and the middleware reads them from Keychain when needed. The action carries no secret data.

**Before (insecure) -- secret travels through the action stream:**

```swift
// DirectAction.swift
case validateClaudeAPIKey(apiKey: String)

// AISettingsView.swift
store.dispatch(.validateClaudeAPIKey(apiKey: key))

// ClaudeMiddleware.swift
case .validateClaudeAPIKey(apiKey: let apiKey):
    // apiKey extracted from action -- visible in logs
```

**After (secure) -- action is a signal only, secret stays in Keychain:**

```swift
// DirectAction.swift -- no associated value
case validateClaudeAPIKey

// AISettingsView.swift -- save to Keychain FIRST, then dispatch
try? KeychainService.save(key: ClaudeService.keychainKey, value: key)
store.dispatch(.validateClaudeAPIKey)

// ClaudeMiddleware.swift -- read from Keychain at point of use
case .validateClaudeAPIKey:
    return Future<DirectAction, DirectError> { promise in
        Task {
            guard let apiKey = KeychainService.read(key: ClaudeService.keychainKey),
                  !apiKey.isEmpty
            else {
                promise(.success(.setClaudeAPIKeyValid(isValid: false)))
                return
            }
            do {
                try await service.value.validateAPIKey(apiKey)
                promise(.success(.setClaudeAPIKeyValid(isValid: true)))
            } catch {
                if case ClaudeError.invalidAPIKey = error {
                    KeychainService.delete(key: ClaudeService.keychainKey)
                }
                promise(.success(.setClaudeAPIKeyValid(isValid: false)))
            }
        }
    }.eraseToAnyPublisher()
```

### The General Pattern

```
View -> Keychain.save(secret) -> store.dispatch(.actionWithNoSecret)
                                        |
Middleware <- Keychain.read(secret) <- receives action
          -> makes API call with secret
          -> dispatches result action (no secret in result either)
```

**Rule: never put a secret in an action's associated value.** Use the Keychain (or any secure out-of-band storage) as a side channel.

## Related Fixes

### Error Sanitization
Raw API response bodies can contain tokens or internal details. Strip them:

```swift
// Before: raw message in error
case apiError(statusCode: Int, message: String)

// After: status code only
case apiError(statusCode: Int)
```

### CSV Formula Injection
User-provided strings (meal descriptions) in CSV exports need sanitization:

```swift
private func escapeCSVField(_ field: String) -> String {
    var sanitized = field
    while let first = sanitized.first, "=+@-\t\r".contains(first) {
        sanitized = String(sanitized.dropFirst())
    }
    if sanitized.contains(",") || sanitized.contains("\"") || sanitized.contains("\n") {
        return "\"\(sanitized.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return sanitized
}
```

### NWPathMonitor Anti-Pattern
`NWPathMonitor().currentPath` read synchronously without `start(queue:)` always returns stale/default state. Removed entirely -- rely on URLSession error handling.

### Main Thread Image Processing
`preparedForVisionAPI()` (image resize + JPEG compression) moved off main thread with `Task.detached` and `MainActor.run` for dispatching results.

## Prevention & Best Practices

| # | Check | Applies to |
|---|-------|-----------|
| 1 | No secrets in `DirectAction` cases or `DirectState` properties | Any middleware or action change |
| 2 | `NWPathMonitor` started before path reads, cancelled on teardown | Network-related code |
| 3 | All new APIs availability-checked against iOS 15.0 target | Any new UI or framework API |
| 4 | User strings CSV-escaped through shared utility | Export features |
| 5 | Image processing off main thread | Any `UIImage`/`CGImage` work |

## Key Files

- `App/Modules/Claude/KeychainService.swift` -- Keychain wrapper (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
- `App/Modules/Claude/ClaudeMiddleware.swift` -- Middleware reads API key from Keychain
- `App/Modules/Claude/ClaudeService.swift` -- Service takes API key as parameter, never stores
- `App/Modules/Log/Log.swift` -- Log middleware with action exclusion list
- `Library/DirectAction.swift` -- Action enum (API key removed from associated value)
- `App/Modules/DataStore/StoreExport.swift` -- CSV injection fix

## References

- Commit `b258c1e8` -- The security fix commit
- Commit `4d4de9b2` -- Original Phase 3 implementation (introduced the bug)
- `docs/development-rules.md` Section 6 -- Security & Privacy rules
- Plan: `docs/plans/2026-03-08-feat-food-logging-healthkit-integration-plan.md`
