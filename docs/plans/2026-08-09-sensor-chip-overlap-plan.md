# Plan — Sensor line chip overlap + Digest timeline colour parity

**Issue:** DMNC-1481 · **Branch:** `fix/sensor-chip-overlap` · **Umbrella:** DMNC-1480

## Intent contract (verbatim user feedback)

> "right now one major layout issue is that the disconnect button is overlapped by other text on the main page in the app."

Two independent visual bugs on the two screens the user looks at most. Both are small and mechanical; neither changes behaviour.

---

## Part 1 — DISCONNECT chip overlap

### Verified root cause

`App/Views/Overview/SensorLineView.swift:23-34` renders the status label and the trailing action chip as **independent ZStack siblings** — they never negotiate layout. The only thing keeping them apart is a hard-coded reservation on line **28**:

```swift
ZStack {
    dotAndLabel
        .lineLimit(1)
        .truncationMode(.middle)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, reservesChipWidth ? 86 : DOSSpacing.md)   // ← line 28, the bug

    HStack {
        Spacer()
        trailingContent
    }
}
```

`86` does not match any chip. SF Mono advance is 0.6em, so 12pt `DOSTypography.caption` = 7.2pt/char; each chip adds 2 × `DOSSpacing.sm` (12) of horizontal padding. The `.overlay(Rectangle().stroke(...))` border contributes **zero** layout width:

| chip | source | chars | text | + padding | **total** | vs 86 |
|---|---|---|---|---|---|---|
| `DISCONNECT` | `:102-116` | 10 | 72.0 | 24 | **96.0** | **10pt short → overlap** |
| `CONNECT` | `:117-131` | 7 | 50.4 | 24 | **74.4** | 11.6pt over-reserved |
| `SET UP` | `:132-140` | 6 | 43.2 | 24 | **67.2** | 18.8pt over-reserved |

**Overlap proof (iPhone 17 Pro, 402pt).** Content width after the outer `DOSSpacing.md` padding (`:35`) is 370pt. With `reservesChipWidth == true` the label band is 370 − 172 = 198pt centred, spanning x ∈ [86, 284]. The right-aligned DISCONNECT chip spans x ∈ [274, 370].
- `"CONNECTED · 13d 21h LEFT"` (fresh 14-day sensor) = 24 chars ≈ 173pt text + 7pt dot + 4pt `DOSSpacing.xxs` = **~184pt** → centres to [93, 277] → **3pt into the chip**.
- Same label with the night-profile `moon.fill` (`:75-80`, +~16pt) = **~200pt** → **~11pt overlap**, and it now exceeds the 198pt band so `minimumScaleFactor` also kicks in.
- iPhone 16e (390pt) is strictly worse. **Verify on 16e.**

**Why it regressed:** `68e51c19` ("show full sensor remaining time") changed an unconditional `.padding(.horizontal, 86)` into the conditional form, introduced `inTimeCompact`, and added `minimumScaleFactor(0.85)`. The longer label plus the removal of hard truncation exposed that 86 < 96 all along.

**Why a constant cannot be the fix.** `DOSTypography.caption` is `Font.system(size: 12, …)` (`Library/DesignSystem/DOSTypography.swift:53`) so it **scales with Dynamic Type**, and there is **no `.dynamicTypeSize` clamp anywhere in App/, Library/, or Widgets/** (verified: zero hits). At accessibility sizes the chip is 2.5–3× wider. Any hard-coded number re-breaks silently on the next copy or type-scale change — that is exactly the regression class being fixed.

### Approach: measure the chip, derive the reservation

**There is no width-measurement precedent in this codebase.** Verified zero hits for `PreferenceKey`, `.preference(key:`, `onPreferenceChange`, `onGeometryChange`, `alignmentGuide`, `ViewThatFits`, and `background(GeometryReader`. All nine existing `GeometryReader` sites read the *container's* `geo.size` to size a fill; none propagate a measured child size upward. So write it explicitly — do not go looking for a helper to reuse.

1. Add a file-private `PreferenceKey` in `SensorLineView.swift`:
   ```swift
   private struct ChipWidthKey: PreferenceKey {
       static var defaultValue: CGFloat = 0
       static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
           value = max(value, nextValue())
       }
   }
   ```
   `max` (not last-wins) so a transient 0 from a disappearing chip cannot collapse the reservation mid-transition.

2. Publish the chip's width from the trailing layer — attach to the `HStack` wrapping `trailingContent` at `:30-33`:
   ```swift
   .background(
       GeometryReader { geo in
           Color.clear.preference(key: ChipWidthKey.self, value: geo.size.width)
       }
   )
   ```
   `Color.clear` is fine — StyleGuard rule 3 bans `Color.black`, not `Color.clear`.

3. Read it into `@State private var measuredChipWidth: CGFloat = 0` via `.onPreferenceChange(ChipWidthKey.self) { measuredChipWidth = $0 }` on the `ZStack`.

4. Replace line 28 with a derived reservation:
   ```swift
   .padding(.horizontal, reservesChipWidth ? max(measuredChipWidth, DOSSpacing.md) : DOSSpacing.md)
   ```
   `max(_, DOSSpacing.md)` covers the first render pass, when `measuredChipWidth` is still 0.

5. Add `.fixedSize()` to each of the three chip labels (`:102-116`, `:117-131`, `:132-140`) so the measured width is the chip's **intrinsic** width and cannot itself be compressed by the parent. Precedent: `GlucoseStatusBar.swift:217`, `CollapsableSection.swift:88`.

### Must not change

- The optical-centering design and its rationale comment at `SensorLineView.swift:15-22` — the label stays centred; only the reservation's *source* changes. Update the comment to say the reservation is measured, not hard-coded.
- `minimumScaleFactor(0.85)`, `lineLimit(1)`, `truncationMode(.middle)` — the safety net stays.
- `reservesChipWidth` (`:202-210`) semantics: chip-less states keep the cheap `DOSSpacing.md`.
- Tap-to-reveal behaviour (`handleRowTap`, `:239-250`), the disconnect alert (`:47-55`), the connect dialog (`:56-68`), and all accessibility strings (`:254-282`).

### Known-acceptable

One extra layout pass on chip reveal/hide (preference → state → re-layout). This row re-renders on every glucose publish (~1/min) anyway; a single settle frame on a user-initiated tap is not perceptible. If the chip visibly jumps on reveal, wrap the state write in `withAnimation(AnimationTokens.easeSnap)` — **never** an inline curve (StyleGuard rule 7).

---

## Part 2 — Digest timeline colour parity

`App/Views/DigestView.swift:486-521` (`buildTimelineItems`) hard-codes event colours that are **cyclically permuted** against the canonical `EventMarkerType.color` (`Library/Content/EventMarker.swift:30-38`). The same event is a different colour on Overview and on Digest, one tab apart:

| event | Overview marker lane (canonical) | Digest timeline (wrong) |
|---|---|---|
| meal | `cgaGreen` | `amber` (`DigestView.swift:498`) |
| insulin | `amber` / `amberLight` / `amberDark` by sub-type | `cgaCyan` (`:507`) |
| exercise | `cgaCyan` | `cgaGreen` (`:516`) |

**Fix:** route all three through the canonical token. The `InsulinType → EventMarkerType` bridge already exists — `Library/Content/EventMarker.swift:79-85`, `var markerType`, already used by `ChartView.swift:959` — so insulin maps by sub-type for free:

- meals → `EventMarkerType.meal.color`
- insulin → `ins.type.markerType.color` (mealBolus/snackBolus → amber, correctionBolus → amberLight, basal → amberDark)
- exercise → `EventMarkerType.exercise.color`

Do **not** add a new mapping function and do **not** change `EventMarkerType.color` — the marker lane is canonical and correct.

---

## Tasks

- [ ] Read `App/Views/Overview/SensorLineView.swift` in full before editing.
- [ ] Add `ChipWidthKey` PreferenceKey (file-private).
- [ ] Publish chip width from the trailing `HStack` via `GeometryReader` + `Color.clear.preference`.
- [ ] Add `@State measuredChipWidth` + `.onPreferenceChange` on the ZStack.
- [ ] Replace the `86` literal on `:28` with `max(measuredChipWidth, DOSSpacing.md)`.
- [ ] Add `.fixedSize()` to all three chip labels.
- [ ] Update the rationale comment at `:15-22` to describe the measured reservation.
- [ ] `DigestView.buildTimelineItems`: route meal / insulin / exercise colours through `EventMarkerType.color`, insulin via `.markerType`.
- [ ] Add tests to **`DOSBTSTests/SensorTests.swift`** (already registered in pbxproj at `:24, :117, :287, :509`). Pin what is pinnable without a view host: the `InsulinType.markerType → color` mapping for all four insulin cases, and that `EventMarkerType.meal.color != EventMarkerType.exercise.color` etc. **Do not create a new test file** — that needs four manual `project.pbxproj` edits and buys nothing here.
- [ ] `CHANGELOG.md` → `## [Unreleased]` → `### Fixed`, two entries, each tagged `— DMNC-1481, PR #NN`.
- [ ] Full build + test run (below), with output pasted into `IMPLEMENTATION_NOTES.md`.

## Verification

```bash
xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSApp \
  -destination 'id=00C020D3-A83B-4E78-98F9-A9AA4AAE8673' -configuration Debug build

xcodebuild test -project DOSBTS.xcodeproj -scheme DOSBTSApp \
  -destination 'id=00C020D3-A83B-4E78-98F9-A9AA4AAE8673'
```

That UDID is **iPhone 16e / iOS 26.2** — the narrowest available screen and therefore the best overlap reproduction. Device names repeat across three installed runtimes, so always target by `id=`, never `name=`.

`StyleGuardTests` runs inside that suite and fails on: `.font(.system(` (rule 1), semantic Dynamic Type fonts (2), `Color.black` (3), `.foregroundColor(` (4), `cornerRadius` (5), `ProgressView()` under `App/Views` (6), inline animation curves (7), raw `Color(red:)` outside `AmberTheme.swift` (8), `header: {` without `.dosHeader(` within 8 lines (9). **The scanner is line-oriented and does not skip trailing comments or string literals** — a banned token inside `// was .cornerRadius(0)` still fails the suite. Keep explanatory comments on their own lines.

**On-simulator checks** (screenshot each, attach to the PR):
1. Connected + chip revealed, fresh-sensor label `CONNECTED · 13d 21h LEFT` → no overlap.
2. Same at `xxxLarge` Dynamic Type → still no overlap.
3. Disconnected (`CONNECT` chip) and no-sensor (`SET UP` chip) → label centred, not over-truncated (this is the visible *improvement* from removing the 86pt over-reservation).
4. Tap to reveal / hide the chip repeatedly → no flicker, no stuck reservation.
5. Digest tab timeline with a meal, a bolus, a correction, a basal, and an exercise entry → colours match the Overview marker lane.

## Out of scope

- The three chips hand-roll `.overlay(Rectangle().stroke(...))`, which CLAUDE.md forbids, and a shared `AmberChipLabel` exists at `Library/DesignSystem/Components/AmberChip.swift:13`. **Leave it alone** — it is not guard-enforced, and swapping it changes chip metrics. Noted for a future sweep.
- Any `.dynamicTypeSize` clamp (app-wide policy decision, not this fix).
- Any change to `EventMarkerType`, the marker lane, or `ChartView`.
- Adding note/other event types to the digest timeline.
