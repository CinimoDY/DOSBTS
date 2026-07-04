# Decisions — DMNC-1295

## restore* actions instead of reusing add* for undo

**Chose** to add three new dedicated actions (`restoreBloodGlucose`, `restoreInsulinDelivery`, `restoreSensorGlucose`) **over** reusing the existing `add*` actions for swipe-delete undo.

**Why:** The `add*` actions are overloaded — they signal "a new live entry arrived." Middlewares listen on those actions and fire side effects that are only appropriate for live readings: alarm evaluation (GlucoseNotification), voice readout (ReadAloud), HealthKit export, Nightscout upload, missed-bolus nudge cancellation (MissedBolusMiddleware), treatment cycle re-evaluation, and streak detection. Re-dispatching `.addSensorGlucose` for a historical undo would speak the old value aloud, potentially trigger an alarm for an out-of-range value that was hours ago, and duplicate the entry in HealthKit and Nightscout. The restore actions are handled only by their respective DataStore middlewares (insert to GRDB + emit loadXxx), bypassing all side-effect middlewares without any conditional guard.

## swipeActions over onDelete for all three list types

**Chose** `.swipeActions(edge: .trailing)` with a `.destructive` button **over** the `.onDelete(perform:)` modifier on `ForEach`.

**Why:** `.onDelete` is a system gesture that invokes the block with an `IndexSet` — useful for simple deletion, but offers no way to inject additional behaviour (toast display, local state update, store dispatch) at the same time without indirection. `.swipeActions` puts all three actions — list state remove, store dispatch, and toast show — in a single inline closure, which is cleaner and avoids the index-based offset conversion. It also lets the button carry a `role: .destructive` for the standard red colour without manually styling.

## swipe-dismiss protection scope: entry sheets only

**Chose** to apply `.interactiveDismissDisabled()` to `AddInsulinView`, `AddBloodGlucoseView`, and `AddCalibrationView` **over** extending it to picker/chooser sheets (e.g. `UnifiedFoodEntryView`).

**Why:** The three protected sheets have mandatory numeric inputs (units, glucose value) where a swipe-dismiss silently discards mid-entry data with no undo path. `AddMealView` was already protected. `UnifiedFoodEntryView` is a selection-based sheet (the user picks from a list) with no partial-input state to lose — protecting it would make dismissal feel sluggish without safety benefit.
