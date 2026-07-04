# Themes — DMNC-1294 Feedback Parity

## Theme 1: Generalising the toast

The existing `LoggedMealToast` was tightly coupled to `MealEntry` and lived inside the food-entry sheet (which stays open for quick-logs). Quick-logged meals already had a toast; the other three paths logged silently.

The fix introduced a `LoggedEntry` enum (`meal`, `insulin`, `bloodGlucose`) and a `LoggedEntryToastController` with a **stage/show** split: the callback stages the entry before the sheet dismisses, and ContentView's `onDismiss` promotes it to active. This means the toast always appears *after* the sheet is fully gone — no z-order fights with the modal presentation layer.

## Theme 2: Haptic parity

`DirectNotifications.shared.hapticNotification(.success)` was already present in the AI/barcode path. Added it to all four log callbacks: `logFavorite`, `logRecent`, and the insulin/BG/manual-meal paths.

## Theme 3: Keeping quick-log UX intact

The in-sheet `LoggedMealToast` for favorites/recents was not touched — those sheets stay open so the user can log multiple items, and the local controller handles the in-flight toast correctly. Only haptic was added there.
