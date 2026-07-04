# Themes — DMNC-1295

## Middleware side-effect contamination is the primary risk in undo flows

When actions are overloaded to mean both "new live event" and "restore historical entry," middlewares designed for the live path silently trigger on restores. The pattern to watch: any undo/restore path that dispatches an `add*` action should be audited against every middleware that handles that action. In this codebase, sensor glucose is the highest-risk case (14+ side-effect middlewares), blood glucose is medium risk (Nightscout + HealthKit), and insulin is low risk (MissedBolus nudge cancellation only).

## loggedEntryToast needs to be at TabView scope, not sheet scope

The `loggedEntryToast` controller must be injected at the TabView modifier chain level (alongside `sheets` and `addedHighlighter`) so that List views in non-Overview tabs can access it via `@EnvironmentObject`. Injecting it only into sheets (via RootSheetContent) leaves tab-level list views without access.
