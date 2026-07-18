# Implementation Notes

## 2026-07-18 — DMNC-1414 Marker detail sheet: per-entry times, swipe-delete, per-row edit

Plan: `docs/plans/2026-07-18-marker-detail-selective-edit-plan.md`

**Setup correction (logged for transparency):** the feature branch was initially
created in the shared checkout (`/Users/doke/extracode/DOSBTS`) by mistake; moved it
into this worktree and restored the shared checkout to `main` before any file edits.
No changes were lost (all at clean commit a9608c57).

**Decisions (judgment areas granted by brief):**

- **ScrollView→List styling.** Converted the rows region from `ScrollView`+`VStack`
  to `List(.plain)` with `.scrollContentBackground(.hidden)`,
  `.listRowBackground(AmberTheme.dosBlack)` (black rows), and
  `.listRowSeparatorTint(AmberTheme.borderSubtle)` (amber separators — matches the
  previous `Divider().background(AmberTheme.borderSubtle)` look). The header stays
  ABOVE the List (not a section header) with the same `Divider().background(amberDark)`
  underline, preserving the exact prior top chrome. `okBar` stays in
  `safeAreaInset(edge: .bottom)`. Row spacing preserved via
  `.listRowInsets(top: sm, leading: md, bottom: sm, trailing: md)` matching the old
  `.padding(.horizontal, md).padding(.vertical, sm)`.

- **Per-row time placement.** Chose the **trailing VStack under the value column**
  (value on top, `HH:mm` caption in `amberDark` beneath it), applied identically to
  ALL row types (meal / insulin / exercise) for consistency. Rejected "leading the
  subline" because meal sublines can be empty, which would leave the time visually
  orphaned or force an em-dash separator.

- **Undo toast: `stage()` not `show()`.** The Lists-tab insulin swipe-delete calls
  `loggedEntryToast.show(.deletedInsulin(...))` because it runs on a normal tab. Here
  the swipe happens INSIDE a `.sheet`, and the toast overlay lives on ContentView
  BEHIND the sheet — a `show()` would burn its 3s auto-dismiss timer occluded and the
  UNDO would be lost. So `onDeleteEntry` for insulin uses
  `loggedEntryToast.stage(.deletedInsulin(delivery))`; ContentView's sheet `onDismiss`
  already calls `showStagedIfAny()`, so the UNDO toast surfaces the moment the sheet
  closes (last-row-deleted self-dismiss, or user taps OK). Meal/exercise deletes have
  no `LoggedEntry` undo case (matching the Lists-tab meal delete, which also has none),
  so they just delete — adding `.deletedMeal` was flagged optional in the plan and is
  out of scope.

- **Empty subline now conditionally hidden.** Previously an empty subline rendered as
  an invisible empty `Text`. Now rendered only when non-empty (cleaner spacing). No
  test impact — tests only pin the static `subline(for:)` string helper.
