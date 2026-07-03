---
title: "safeAreaInset applied outside a NavigationStack does not propagate to pushed destination views"
date: 2026-07-04
category: ui-bugs
module: "App/Views/SharedViews/GlucoseStatusBar"
problem_type: ui_bug
component: frontend_stimulus
symptoms:
  - "Last row of a List or ScrollView on a pushed screen scrolls behind a persistent bottom bar"
  - "Root tab content clears the bar correctly but navigating forward breaks scroll clearance"
  - "Behavior differs between tabs depending on whether the view has a NavigationStack"
root_cause: logic_error
resolution_type: code_fix
severity: medium
tags: [swiftui, navigationstack, safeareainset, list, scroll, persistent-bar, pushed-views]
---

# `safeAreaInset` applied outside a `NavigationStack` does not propagate to pushed destination views

## Problem

Applying `.safeAreaInset(edge: .bottom)` to a `NavigationStack` from the outside — i.e., as a modifier on the stack's container — does not propagate to views pushed onto the stack. The root view may correctly scroll its last row above the bar, but any pushed destination view (a detail screen, a settings category, a calibration list) does not know about the inset and lets content scroll underneath the bar.

## Symptoms

- Scrolling to the bottom of a root `List` clears the persistent bar correctly.
- Navigating forward (NavigationLink or `.navigationDestination`) and scrolling the pushed view shows the last row partially or fully behind the bar.
- The bug is invisible in Xcode Preview (no navigation push happens).
- Differs per tab: a `ScrollView` tab with its own `.safeAreaInset` works fine; `List`-backed tabs using a shared shell hit this.

## What Didn't Work

Placing `.safeAreaInset { GlucoseStatusBar() }` on the `NavigationStack` view (from the parent VStack) — the root content scrolls correctly, but pushed views still scroll under the bar. The modifier is applied to the `UIHostingController` that hosts the `NavigationStack`, not to the `UINavigationController` itself, so pushed view controllers start with their own zeroed `additionalSafeAreaInsets`.

## Solution

Move `NavigationStack` ownership inside the shared shell (e.g., `GlucoseFramedTab`) and apply `.safeAreaInset` to the root **content inside** the `NavigationStack`, not to the stack from outside.

```swift
// ✗ Before — inset is on the NavigationStack from outside; pushed views don't inherit it
struct GlucoseFramedTab<Content: View>: View {
    var body: some View {
        VStack(spacing: 0) {
            GlucoseTopBar()
            content()                                    // caller passes NavigationStack
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    GlucoseStatusBar()
                }
        }
    }
}

// ✓ After — shell owns NavigationStack; inset is inside the stack on root content
struct GlucoseFramedTab<Content: View>: View {
    var body: some View {
        VStack(spacing: 0) {
            GlucoseTopBar()
            NavigationStack {
                content()                               // caller passes root List/ScrollView only
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        GlucoseStatusBar()
                    }
            }
        }
        .background(AmberTheme.dosBlack)
    }
}
```

Call sites (e.g., `ListsView`, `SettingsView`) pass the root `List` directly — **do not wrap in a `NavigationStack`** at the call site.

## Why This Works

SwiftUI translates a `safeAreaInset` applied to a view **inside** a `NavigationStack` into `additionalSafeAreaInsets` on the `UINavigationController`. That property IS inherited by every pushed `UIViewController` on the stack, so all destination views automatically account for the bar height without any per-screen changes.

When the inset is applied to the `NavigationStack` from outside, it lands on the wrapping `UIHostingController` — not the nav controller — and pushed view controllers are unaware of it.

## Prevention

- **GlucoseFramedTab owns the NavigationStack.** Call sites must not wrap content in a NavigationStack before passing it to `GlucoseFramedTab`. Enforced by doc comment only (no compile-time guard is feasible in SwiftUI generics); review call sites when adding new tabs.
- For tabs that don't use `GlucoseFramedTab` (Overview, Digest), the bar is mounted directly via `safeAreaInset` on the root VStack/ScrollView — no NavigationStack is involved, so the propagation issue doesn't apply.
- See also: `docs/solutions/ui-bugs/swiftui-vstack-overflow-sinks-safeareainset.md` for the related VStack-overflow variant of the safeAreaInset problem in Overview.

---

## Secondary Finding: `Divider().background(color)` does not colour the separator line

### Problem

`Divider().background(AmberTheme.dosBorder)` applies a background layer **behind** the Divider element. SwiftUI's `Divider` always renders its separator line in the system separator colour (a semi-transparent gray/white) regardless of `.background`. The intended amber border colour does not appear.

### Solution

Replace `Divider()` with a 1pt filled `Rectangle`, matching the pattern used in `GlucoseTopBar`:

```swift
// ✗ Does not colour the line
Divider()
    .background(AmberTheme.dosBorder)

// ✓ Correctly fills the 1pt separator
Rectangle()
    .fill(AmberTheme.dosBorder)
    .frame(height: 1)
```

### Prevention

Never use `.background(color)` to change a `Divider`'s line colour. When a themed separator is needed, always use `Rectangle().fill(token).frame(height: 1)`.
