# DMNC-1312 — Entry-sheet chrome consolidation + chevron rule

**Date:** 2026-07-04  
**Branch:** claude/dmnc-1312  
**Commit:** b3545369

## What changed

AddInsulinView was the only entry sheet with a hand-rolled nav bar — an HStack containing
Cancel/title/Add with a manual borderFaint underline. The other four entry surfaces (meal,
blood glucose, calibration, filtered food entry) all use the system pattern: NavigationStack +
`.dosNavigationTitle` + `.toolbar` with ToolbarItems. This made insulin look subtly different
and required 28 lines of custom chrome to maintain.

Migrated to the family pattern. The ScrollView now lives inside a NavigationStack; title and
toolbar attach to the scroll view so the parent stack's bar hosts them — same technique as
AddBloodGlucoseView. Net: −24 lines, visual parity across all five surfaces.

Also enforced the chevron rule throughout the meal entry sheet and shared meal rows:
**a chevron only where something expands or navigates; the word alone everywhere else.**

Three section headers in UnifiedFoodEntryView (QUICK, RECENT, OTHER) carried a plain
`Text("> ")` that conveyed no interaction — removed. The QUICK header's actual rotating
`Image(systemName: "chevron.right")` was kept because it does expand. The compact meal row
in MealItemRow had a `"> "` prefix that the code itself described as "a decorative DOS
affordance" — removed. The Log Meal hub's Done button was explicitly left alone (correct:
browse-and-log, non-mutating close).

## Why it matters

Chrome consistency eliminates a class of future one-off divergences. The chevron rule
clarification removes visual noise that was ambiguous: did `> RECENT` mean something was
expandable? It didn't. Now nothing implies a behaviour it doesn't have.

## Tests

Full suite green (350+ tests). StyleGuardTests pass. Widget build clean.
`grep '"> "' App/` → one docstring comment in DigestView only.
