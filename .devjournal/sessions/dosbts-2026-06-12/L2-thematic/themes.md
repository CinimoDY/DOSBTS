# Themes — DMNC-1039

## Visual consistency: secondary-status rows

The alarm snooze/screen-lock row in GlucoseView rendered at the default 17pt body
size because it had no explicit font modifier. The treatment countdown banner directly
below it (TreatmentBannerView) uses DOSTypography.caption (12pt) throughout. The size
mismatch made the snooze indicator visually dominant over the hypo treatment info,
inverting their relative importance.

Fix: one-line addition of `.font(DOSTypography.caption)` to the HStack container,
cascading 12pt to all Text and SF Symbol children within the snooze/screen-lock row.
