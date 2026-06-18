# Decisions — DMNC-1045

## endMarker: 15 minutes flat instead of 1 hour

**Chose** uniform 15-min buffer over restoring the zoom-level conditional.

**Why:** The `level == 1` branch (15 min) was dead code — no configured zoom level has `level == 1`. The 1-hour padding was the only live path, creating a large visible gap. 15 min is enough to give the rightmost reading a little breathing room and still keep the prediction line endpoint (+20 min) visible (the chart domain auto-extends to include LineMark data).

## Canvas for dashed HR legend swatch

**Chose** `Canvas { context, size in ... }` over `RoundedRectangle` + overlay.

**Why:** The HR series in the chart uses `StrokeStyle(lineWidth: 1, dash: [4, 3])`. A solid rectangle doesn't represent that. `Canvas` lets us draw an exact dashed stroke with the same dash pattern, making the legend an accurate representation of the plotted line.

## No `DOSTypography` migration for 9pt legend labels

The `font(.system(size: 9, ...))` calls in the legend were pre-existing. Not changed here — migration to `DOSTypography.mono(size:weight:)` is a separate cleanup concern and not blocking for this fix.
