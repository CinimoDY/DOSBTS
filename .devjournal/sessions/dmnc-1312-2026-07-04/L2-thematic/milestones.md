# Milestones — DMNC-1312

## All five entry surfaces share identical chrome — 2026-07-04

Before: insulin used a hand-rolled HStack bar. After: every entry sheet (meal, insulin, blood
glucose, calibration, filtered food entry) uses NavigationStack + .dosNavigationTitle + .toolbar.

## Chevron rule enforced across meal entry surfaces — 2026-07-04

Zero `Text("> ")` blocks remain in App/ source. Chevrons appear only where interaction follows.
