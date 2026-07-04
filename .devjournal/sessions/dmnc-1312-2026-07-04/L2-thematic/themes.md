# Themes — DMNC-1312

## Arc 1: Entry-sheet chrome unification

AddInsulinView was the one outlier among five entry surfaces — it hand-rolled a HStack nav bar
with manual Cancel/title/Add layout + a borderFaint underline divider, while all other sheets
(meal, blood glucose, calibration, filtered food entry) used the system NavigationStack pattern.

Migrated to: NavigationStack → ScrollView → content, with .dosNavigationTitle("Insulin") +
.toolbar { ToolbarItem leading Cancel / trailing Add }. Matches AddBloodGlucoseView exactly.
interactiveDismissDisabled() and the onChange basal-auto-fill logic were preserved.

Net: -24 lines of custom chrome, visual consistency across all five surfaces.

## Arc 2: Chevron rule enforcement — removing decorative "> " prefixes

Three section headers in UnifiedFoodEntryView (QUICK, RECENT, OTHER) and the compact meal row
in MealItemRow carried a plain `Text("> ")` prefix with no interactive meaning — a leftover DOS
aesthetic that predates the chevron rule: "a chevron only where something expands or navigates."

The QUICK header correctly kept its rotating `Image(systemName: "chevron.right")` (it expands
the favourites grid). The bare `"> "` text next to it was the problem — it implied a second
chevron where there's only one.

RECENT and OTHER are non-expandable headers; their `"> "` was pure decoration.
The compact meal row's `"> "` was described in the code as "a decorative DOS affordance" —
the very definition of the pattern to kill.

All four removed. Grep `'"> '` under App/ now returns one hit: a docstring comment in
DigestView.swift (legitimate prose).
