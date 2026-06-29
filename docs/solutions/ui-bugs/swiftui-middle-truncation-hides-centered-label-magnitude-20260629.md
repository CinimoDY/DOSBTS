---
title: Middle truncation + over-reserved chip padding hides the important part of a centered label
category: ui-bugs
tags: [swiftui, truncation, lineLimit, layout, padding, minimumScaleFactor, sensor]
module: App/Views/Overview/SensorLineView
symptom: "Overview sensor line read '…18min LEFT' for a sensor that actually had 3d 2h 18min remaining"
root_cause: "A centered single-line label reserved fixed chip width on BOTH sides even when no chip was shown, overflowing the available width; .truncationMode(.middle) then removed the most significant middle of the string (the days/hours), leaving only the least significant tail"
severity: high
platform: iOS 26
date: 2026-06-29
---

# Middle Truncation Hides a Centered Label's Magnitude

## Problem

The Overview sensor status line showed the remaining sensor lifetime as if only
minutes were left (e.g. "CONNECTED · …18min LEFT") when the sensor actually had
~3 days, 2 hours, 18 minutes remaining. For a CGM app this is dangerously
misleading — it reads as "replace the sensor now."

## Symptoms

- A multi-day sensor displays only a minutes value on the Overview sensor line.
- The label is centered and single-line; the prefix ("CONNECTED · ") and the
  suffix ("…min LEFT") survive, but the days/hours in the middle vanish.

## What Didn't Work / False Leads

- **Localization keys.** The `inTime` formatter (`Library/Extensions/Int.swift`)
  references `"%1$@h %2$@min"` / `"%1$@min"` keys that are absent from the
  `.strings` files. This looks like the culprit, but NSLocalizedString returns
  the key itself as a fallback, which is a valid format string — and a
  multi-day value takes the `inDays > 0` branch whose 3-part key DOES exist.
  `String(format:)` was verified to produce `"3d 2h 18min"` correctly. The
  formatting was never the bug.

## Root Cause

In `SensorLineView` the centered label was laid out as:

```swift
ZStack {
    dotAndLabel
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 86)   // reserved on BOTH sides to keep optical centering next to a trailing chip
    HStack { Spacer(); trailingContent }   // the chip (often EmptyView)
}
```

Two compounding factors:

1. **Padding reserved unconditionally.** The 86pt was reserved on *both* sides so
   the centered text stays optically centered next to the trailing action chip —
   but it was reserved even in the common connected state where **no chip is
   shown**, wasting ~172pt of width and forcing the label to overflow.
2. **`inTime` always appends minutes when days are present** → a 3-component
   string ("3d 2h 18min"), wider than the view's own design comment assumed
   ("13d 21h LEFT").
3. With the text overflowing, **`.truncationMode(.middle)` removes the middle** —
   exactly the days/hours — leaving the least-significant tail ("…18min LEFT").

## Solution

1. **Compact format for width-constrained labels.** Added `inTimeCompact` that
   drops minutes once days are present (`"3d 2h"`), keeping hour+minute precision
   below a day. Used it on the visible label (kept full `inTime` for the
   VoiceOver string, which is not width-constrained).
2. **Reserve chip width only when a chip is actually shown.** A
   `reservesChipWidth` helper drives `.padding(.horizontal, reservesChipWidth ? 86 : DOSSpacing.md)`,
   so the chip-less connected state gets full width.
3. **`.minimumScaleFactor(0.85)` safety net** so an unusually long string scales
   down rather than dropping characters.

## Why This Works

The most-significant components (days/hours) can no longer be the part that gets
sacrificed: the string is shorter, it has more room, and if it still doesn't fit
the font shrinks instead of truncating.

## Prevention

- **Never put `.truncationMode(.middle)` on a label whose most important
  information is in the middle.** Middle truncation keeps the head and tail; if
  magnitude lives in the middle (most-significant-first numbers), it disappears
  silently. Prefer `.tail`, a shorter string, or `.minimumScaleFactor`.
- **Don't reserve fixed sibling/chip width unconditionally** to fake optical
  centering — reserve it only when the sibling is actually rendered, or the
  centered content pays for empty space that isn't there.
- For numeric magnitudes in tight spaces, drop the least-significant unit (a
  multi-day duration doesn't need minutes) rather than relying on truncation.

## Related Issues

- `docs/solutions/ui-bugs/swiftui-vstack-overflow-sinks-safeareainset.md` — other
  layout-overflow gotcha on the Overview screen.
- Pinned by `InTimeCompactTests` in `DOSBTSTests/SensorTests.swift`.
- Shipped in Build 117 (DMNC tracking n/a — direct dogfood fix).
