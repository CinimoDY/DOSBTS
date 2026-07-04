# Decisions — DMNC-1317

## Band stays fixed at 80–120 (Dominic, 2026-07-04)

Chose fixed band over configurable. "It is a tight streak and it doesn't happen too often with me but that's okay." A configurable band would add settings surface area and weaken the semantic meaning of the achievement.

Added `// fixed by design — DMNC-1317` comments to the literals in `TightControlConfig.resolved()` and updated the struct doc comment to prevent future configurability creep.

## Reference band constants from TightControlConfig.default rather than hardcoding in views

Chose `TightControlConfig.default.bandLow/bandHigh` over hardcoded `80`/`120` in the view layer. Ties display to the single source of truth so a future constant change (if ever — fixed by design, but still) would automatically propagate to the UI.
