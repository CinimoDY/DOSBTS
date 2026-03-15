# Staging Plate UI Pattern

Reference for Phase 5 implementation. The "staging plate" (often referred to simply as the "Plate" in apps like MacroFactor) is a sophisticated UI pattern designed to increase interaction efficiency and reduce cognitive load.

## How It Works

Instead of adding a food directly to the diary and immediately closing the search screen, the app places selected items into a temporary staging area or "base".

## UX Benefits

### Contextual Meal Building
It mimics the real-life experience of looking at an actual plate, allowing users to see all the ingredients they've selected for a specific meal at once.

### Cumulative Macro Review
The staging plate often features a "nutrition banner" or summary that calculates the total calories and macronutrients of the entire complex meal before it is officially logged. This helps users immediately see how the combined meal will impact their daily nutritional budget.

### Centralized Adjustments
From this single view, users can easily edit the portion sizes and serving quantities for multiple ingredients while keeping the context of the overall meal in plain sight.

### Batch-Logging (Reduced Friction)
Instead of navigating back and forth between the search menu and the main diary for every single ingredient, users can add everything to their staging plate and batch-log the entire meal with one final confirmation tap.

### Minified Views
Some apps offer a "minified plate" — a compact version that persists at the bottom of the screen to provide live visual feedback. This allows users to continuously search, scan barcodes, and build a full meal without ever leaving the action menu.

## Implementation Notes for DOSBTS

- Deferred from Phase 4 (YAGNI — ship favorites/recents first, validate need)
- Planned for Phase 5 alongside food database search + barcode scanning
- When logged, plate produces one aggregated MealEntry with concatenated descriptions and summed macros
- Plate state should be ephemeral (Redux state or @State, not persisted)
- Apply portion multipliers at log time, not in state (avoids floating-point drift)
- Truncate concatenated description to ~500 chars for HealthKit metadata safety
- See brainstorm: `docs/brainstorms/2026-03-15-food-logging-overhaul-brainstorm.md`
