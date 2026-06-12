# Decisions — DMNC-1039

## Container-level vs per-label font

Chose to apply `.font(DOSTypography.caption)` on the HStack container rather than
individually on each Text/Image child. Rationale: the entire row is a secondary-status
area — every element within it should be caption-sized. A container modifier is
cleaner and less brittle than per-label repetition.

TreatmentBannerView applies font per-Text, but that's because its content is richer
(multiple font sizes could be desired within a single banner state). The snooze row
is simpler and uniform, so container scoping is appropriate here.

Code review verified: SF Symbols inside the row scale with the inherited caption
font, matching how TreatmentBannerView's xmark dismiss icon works (also caption-sized).
