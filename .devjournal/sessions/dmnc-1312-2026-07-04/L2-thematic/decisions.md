# Decisions — DMNC-1312

## Chose NavigationStack + .dosNavigationTitle over keeping the custom HStack bar

The custom nav bar was 28 lines and matched the system appearance closely but had subtle
divergences: title font was 13pt/semibold vs the system bar's .dosNavigationTitle size, the
Add button used explicit `.foregroundStyle(amber/borderSubtle)` toggling, and the borderFaint
underline was a manual overlay rectangle. The system toolbar provides the underline for free
and handles disabled-state tinting natively. Aligning to the pattern means zero custom chrome
maintenance going forward.

## Chose to attach title + toolbar to the ScrollView (not the NavigationStack outer)

Pattern from AddMealView (which is pushed onto a caller's NavigationStack) vs AddBloodGlucoseView
(which owns its own NavigationStack). Since AddInsulinView is always presented as a sheet with
no parent stack, it owns its NavigationStack. Modifiers go on the inner ScrollView, matching
AddBloodGlucoseView exactly.

## Kept .foregroundStyle on the Add toolbar button

The spec said "keep the visual disabled state if toolbar styling allows, else rely on .disabled".
Both .disabled and .foregroundStyle are kept — .disabled prevents the tap, .foregroundStyle
gives the explicit amber/borderSubtle contrast that matches the other sheets.

## Removed the explanatory comment from MealItemRow alongside the "> " prefix

The comment ("Deliberately dim: the prompt glyph is a decorative DOS affordance...") justified
keeping the prefix. Once the prefix is gone, the comment becomes stale defensive documentation.
Removed both together.

## Log Meal hub kept its "Done" button — not changed

The task spec explicitly records the decision: Done = non-mutating close for a browse-and-log
surface, where the user may tap multiple foods without committing a single transaction. Correct
to leave as-is.
