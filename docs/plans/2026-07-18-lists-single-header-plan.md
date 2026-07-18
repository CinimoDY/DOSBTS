# Lists Tab — Single-Header Collapsible Categories — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**User feedback (verbatim, source of truth for intent):** "In the list tab, where you can see the meals and the insulin listed, there are now two chevrons, and I think we only need one chevron. Maybe the headline could be a bit taller but easier to reach, and then we have the chevron. Maybe we can show the amount of entries just in the top line. Right now, each category looks like it has two chevrons, and it does. I think it's a bit weird because the summary line that is there in the collapse status disappears when you expand, and I don't think we need that summary line. I just think we need that main header for this category, so insulin, and you could show how many entries, and then the chevron to expand, and then the same thing to collapse, same chevron."

**Goal:** Each Lists-tab category renders ONE header row — category name + entry count + a single chevron that toggles expand/collapse — with a taller, easier tap target. The collapsed-state teaser row ("675 Entries" + second chevron) is removed.

**Architecture (verified findings):**
- One shared component drives all five categories (CGM, Blood glucose, Meals, Insulin, Sensor errors): `App/Views/SharedViews/CollapsableSection.swift`.
  - Chevron #1: header `Section(header: HStack { header; Spacer(); Button { chevron.up/down } })` (lines 37-52).
  - Chevron #2 + teaser row: the `if collapsed, collapsible` branch (55-73) renders a `Button` with the teaser text + its own `chevron.down`. Sections default to collapsed (`collapsed: !store.state.listSectionExpanded[key, default: false]`), so two-chevrons is the common state. Expanding skips the branch → the summary line "disappears", exactly as the user describes.
- All five call sites are identical in shape (e.g. `App/Views/Lists/InsulinDeliveryListView.swift:22-34`): `teaser: Text(getTeaser(values.count))`, `header: HStack { Label(...); Spacer(); SelectedDatePager().padding(.trailing) }.buttonStyle(.plain)`, plus `sectionName` / `collapsed` / `collapsible: !values.isEmpty` / `onCollapsedChange` dispatching `.setListSectionExpanded`.
- **Every header embeds `SelectedDatePager`** (defined `App/Views/Lists/StatisticsView.swift:10-47`) with its own prev/next buttons — the toggle tap target must NOT swallow its gestures.
- Counts are already at hand (`values.count` feeds `getTeaser` today).
- Expand state is Redux-persisted: `.setListSectionExpanded` (`Library/DirectAction.swift:190`, reducer `Library/DirectReducer.swift:490-491`, UserDefaults key `libre-direct.settings.list-section-expanded`), pinned at `DOSBTSTests/DirectReducerTests.swift:736-764`. **Stable section keys must not change:** `"CGM"`, `"Blood glucose"`, `"Meals"`, `"Insulin"`, `"Sensor errors"`.
- `CollapsableSection` keeps a local `@State collapsed` seeded once from the init param — the section is its own only writer (comment at lines 17-21). Preserve this one-way-seed design.

**Tech Stack:** SwiftUI, Swift Testing.

## Global Constraints

- Preserve ALL expanded-row behaviors untouched: swipe deletes + undo toasts, insulin row tap-to-edit (`.combinedEntryEdit`), `.dosAddedHighlight`, alarm coloring, `SensorErrorListView`'s offset-based `.onDelete`.
- Preserve the persisted expand/collapse semantics and keys (see above); `onCollapsedChange` wiring unchanged.
- `collapsible: false` (empty section) keeps its meaning: chevron hidden/disabled, header not toggleable.
- StyleGuard Rule 9 (`DOSBTSTests/StyleGuardTests.swift:228-244`): if the refactor introduces a literal `header: {` trailing closure, `.dosHeader(` must appear within 8 lines — satisfy by construction (see Task 1).
- DOS design system: tokens only (`DOSTypography`, `AmberTheme`, `DOSSpacing`); no raw hex, no `.foregroundColor`, no system Dynamic Type fonts (StyleGuardTests enforce).
- User-visible change → `CHANGELOG.md` `[Unreleased]` entry required.

---

### Task 1: Rework `CollapsableSection` — one header row, count, single chevron

**Files:**
- Modify: `App/Views/SharedViews/CollapsableSection.swift`

**New shape:**

```swift
struct CollapsableSection<Label, Accessory, Content>: View {
    init(label: Label,                 // just the category Label (icon + name)
         accessory: Accessory,         // SelectedDatePager — OUTSIDE the toggle button
         sectionName: String,
         count: Int,
         collapsed: Bool = false,
         collapsible: Bool = true,
         onCollapsedChange: ((Bool) -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content)
}
```

- [x] **Step 1:** Delete the entire teaser branch (lines 55-73), the `else if collapsed { teaser }` branch (74-77), the `teaser` property/generic, and the `Teaser == EmptyView` convenience init (92-96) if nothing else uses it (grep first — the five list views are the only known call sites).
- [x] **Step 2:** Header becomes one row: a toggle `Button` wrapping `[label + count + chevron]` with `.contentShape(Rectangle())` and `.frame(minHeight: 44)` (the taller/easier tap target), then `Spacer()`, then `accessory` as a separate hit region so `SelectedDatePager`'s buttons keep working:
  - count rendered like `· 12` in `DOSTypography.caption` / `AmberTheme.amberDark` next to the label (always visible, collapsed or expanded);
  - ONE chevron, flipping with state — collapsed `chevron.down` ("tap to open"), expanded `chevron.up`. Same button both ways (the "same chevron" the user asked for);
  - `collapsible == false` → chevron hidden (`opacity(0)`) and button disabled, as today;
  - VoiceOver on the toggle: `"Expand Meals, 12 entries"` / `"Collapse Meals, 12 entries"`.
- [x] **Step 3:** Body: `if !collapsed { content() }` — nothing else. Keep the one-way-seed `@State collapsed` + `onCollapsedChange` mechanics verbatim.
- [x] **Step 4:** If the restructure ends up using a `header: {` trailing closure form, put `.dosHeader()` on the label inside it (Rule 9); otherwise the existing `Section(header: HStack {...})` form stays exempt.

### Task 2: Update the five call sites

**Files:**
- Modify: `App/Views/Lists/SensorGlucoseListView.swift`, `BloodGlucoseListView.swift`, `MealEntryListView.swift`, `InsulinDeliveryListView.swift`, `SensorErrorListView.swift`

- [x] Per call site: drop `teaser:`; split the old header HStack — the `Label(...)` becomes `label:`, `SelectedDatePager().padding(.trailing)` becomes `accessory:`; pass `count: values.count`. Everything else (sectionName, collapsed, collapsible, onCollapsedChange, content) unchanged.
- [x] The in-content empty-state line (`if values.isEmpty { Text(getTeaser(...)) }`) is now redundant with the header count (`· 0`) — remove it and let empty sections show just the header row. Remove `getTeaser` if it becomes unused (grep).

### Task 3: Tests, CHANGELOG, verification

- [x] Run `StyleGuardTests` + `DirectReducerTests` + full suite → SUCCEEDED (reducer pins at 736-764 must be untouched).
- [x] `CHANGELOG.md` `[Unreleased]` → `### Changed`: `- Log tab categories now use a single taller header row with the entry count inline and one chevron — the duplicate collapsed-state summary line is gone`
- [x] Both targets build.

## Verification (end-to-end, simulator)

1. Log tab, everything collapsed: each category shows exactly ONE row — e.g. `[syringe] Insulin · 12  [date pager]  ⌄` — no second line, no second chevron.
2. Tap the header (anywhere on label/count/chevron) → expands, chevron flips to `⌃`, rows appear directly under the header; count still visible. Tap again → collapses.
3. Date pager prev/next still work independently of the toggle (taps don't collapse the section).
4. Empty category (e.g. Blood glucose with no entries): header shows `· 0`, chevron hidden, not tappable.
5. Kill + relaunch: expand/collapse states persist as before.
