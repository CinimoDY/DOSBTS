# Plan — DB-backed food history search (A1)

**Issue:** DMNC-1484 (lane A1) · **Branch:** `feat/food-history-search` · **Umbrella:** DMNC-1480

## Intent contract (verbatim user feedback)

> "And also keep local histories. You can go further back in recently added food. It should be like an autocomplete right now. It seems like it's just the last 20 items, and anything before that doesn't get pulled up out of memory. This should really be creating our own database, I guess, or keeping more in short-term memory of the app. That would make it really useful."

**This plan is lane A1 only** — make the existing search reach the full history. Lane A2 (promoting `PersonalFood` into a first-class catalog with per-food portion presets) is deliberately deferred until after voice V1; do not start it here.

## Verified root cause

Two caps compound:

1. `App/Modules/DataStore/FavoriteStore.swift:326-353` — `getRecentMealEntries()` name-dedupes via a correlated subquery, then hard-caps at **`LIMIT 20`** (line **343**).
2. `App/Views/AddViews/UnifiedFoodEntryView.swift:420-425` — `filteredRecents` filters only `store.state.recentMealEntries`, i.e. **the same 20 rows**. The section comment at `:410` states the invariant plainly: *"Filtering (local, no Redux dispatch)"*. The search box never touches the database.

So the 21st-most-recent distinct food is unreachable by any means. The dead end the user hits is the string at `UnifiedFoodEntryView.swift:240`: `"No matches for \"\(searchText)\""`.

Meanwhile the data is all there: `MealEntry` is **never pruned**, carries full macros, and the index the query needs already exists — `MealEntry_description_timestamp ON MealEntry(mealDescription COLLATE NOCASE, timestamp DESC)`, created at `FavoriteStore.swift:161-170` for recents and currently exercised only by the dedupe subquery.

## Approach

Keep the fast in-memory path for the common case; fall through to the DB when the user actually searches.

### 1. New DB query — `FavoriteStore.swift`, inside the existing `private extension DataStore` (starts `:107`)

Add `searchMealEntries(matching:limit:)` next to `getRecentMealEntries()`. Copy that function's shape exactly (`:326-353`) but:

- **Use the `guard let dbQueue … else { promise(.success([])); return }` form**, not `getRecentMealEntries`'s `if let dbQueue` — the `if let` form **never fulfils the promise** when `dbQueue` is nil, which would strand the UI. Precedent for the correct form: `RatioLabMiddleware.swift:76-79`.
- **Bind parameters — never interpolate the query text into SQL.** GRDB: `MealEntry.fetchAll(db, sql: "…", arguments: [pattern, limit])`. Existing `arguments:` precedent at `FavoriteStore.swift:292-295`.
- Reuse the same name-dedupe subquery so results are one row per distinct food, newest wins.
- Clamp the incoming query with `.prefix(500)` before it reaches SQL, mirroring the ASK AI clamp at `UnifiedFoodEntryView.swift:383`.
- Escape `%` and `_` in the user's text before building the `LIKE` pattern, or they act as wildcards.

**Matching semantics — a real decision, make it explicitly.** Today's in-memory filter is `localizedCaseInsensitiveContains` (*contains*). The existing index only accelerates **prefix** matching (`LIKE 'q%'`); `LIKE '%q%'` forces a full scan. `MealEntry` is small (one row per logged meal, personal-scale), so **a scan is acceptable — preserve contains semantics** rather than silently narrowing behaviour to prefix-only. Note this choice in a comment so the next reader does not "fix" it.

### 2. Transient search state — follow the `ratioEvidence` template exactly

`ratioEvidence` is the codebase's canonical *transient, on-demand, not-persisted* state. Copy it, do not invent:

| file | anchor | what to add |
|---|---|---|
| `Library/DirectState.swift` | template `:136-140`; array neighbours `:58-60` | `var mealHistoryResults: MealHistoryResults? { get set }` |
| `App/AppState.swift` | template `:331-333` | plain `var mealHistoryResults: MealHistoryResults?` — **no `didSet`, no UserDefaults read in `init`** |
| `Library/DirectReducer.swift` | template `:524-529`; array cluster `:215-232` | one `case .setMealHistoryResults(...)` |
| `Library/DirectAction.swift` | template `:227-230` | `case searchMealHistory(query: String)` + `case setMealHistoryResults(results: MealHistoryResults?)` |

Note the load action gets **no reducer case** — falling through `default:` is what makes "nil == still loading" work (documented at `RatioLabView.swift:28-34`).

**Out-of-order results are a real hazard here and `ratioEvidence` does not face it.** `Store.dispatch` (`Library/Extensions/State.swift:49-72`) fires each middleware publisher and never cancels in-flight work. Typing `ap` then `app` can land the slower `ap` result last, showing wrong rows. **Therefore the payload must carry its query**, e.g.:

```swift
struct MealHistoryResults: Equatable {
    let query: String
    let entries: [MealEntry]
}
```

and the view ignores any result whose `query` != the current trimmed `searchText`. Nothing in the codebase does this today — it is new, and it is required.

### 3. Middleware — extend `favoriteFoodStoreMiddleware`, do not add a new one

Add the `.searchMealHistory` case to the existing middleware in `FavoriteStore.swift` (declared `:10`). **This means no `App/App.swift` edit at all** — the lower-risk option, since that file needs both the device and simulator arrays kept in sync.

Copy the `.loadRecentMealEntries` case at `:78-85`: `guard state.appState == .active else { return Empty()… }`, then one `asyncRead`, no writes inside it (GRDB deadlock rule — `docs/solutions/logic-errors/grdb-write-inside-asyncread-deadlock-20260420.md`). Confirmed clean today: both `asyncRead` blocks in this file (`:309`, `:329`) contain zero writes; keep it that way.

**Copy `RatioLabMiddleware.swift:40-44`'s `.catch { … }.setFailureType(to:)` sandwich.** Without it a GRDB error emits `.failure`, which `Store` only logs and never re-dispatches — so `.setMealHistoryResults` would never land and a nil-means-loading view would spin forever. Fall back to an empty result set for the current query.

Do **not** re-trigger search from `.setAppState(.active)` (`:87-97`) — this is an on-demand load. Follow `ratioLabMiddleware`'s explicit no-re-trigger comment.

### 4. View wiring — `UnifiedFoodEntryView.swift`

- **Debounce.** The only debounce precedent in the codebase is `ChartView.swift:651-658` (`DispatchWorkItem` + `asyncAfter(.milliseconds(100))`, cancelled on each call, driven from eight `.onChange` sites). **Copy that shape** — it is proven and matches house style. Add a new `.onChange(of: searchText)` next to the existing `.onChange(of: store.state.recentMealEntries)` at `:94-100`; the debounce state var goes with the other `@State`s at `:35-40`. ~250ms is right for a DB round-trip (100ms is tuned for local chart math).
- **Gate on the same predicate as ASK AI** — `searchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3` (`:357`) — so history search and ASK AI appear together rather than out of phase. Below 3 chars, keep today's in-memory filter.
- **Merge, don't duplicate.** DB hits will overlap `recentMealEntries`. Dedupe by `mealDescription` (case-insensitive), recents first. Extract this as a **pure struct** (see Tests) — it is the only way to get this change under test.
- **Reuse `MealItemRow(meal:variant: .recent)`** unchanged, and reuse the existing row actions verbatim: `openOnStagingPlate(meal)` on tap, `logRecent(meal)` on hold (`:445-456`). Both take a bare `MealEntry` and have no dependence on the row coming from `recentMealEntries`.
- **Loading indicator must be `FiguresLoadingView.inline`** (`App/Views/SharedViews/FiguresLoadingView.swift:96`) — StyleGuard rule 6 bans `ProgressView()` anywhere under `App/Views`.
- **Any new `Section` header must use `.dosHeader()`** — StyleGuard rule 9 scans for `header: {` without `.dosHeader(` within 8 lines.
- Update the now-false comment at `:410` (*"Filtering (local, no Redux dispatch)"*).
- Reset the search state to `nil` when the query clears and in `onDisappear`, so a stale result set cannot flash on the next open of the sheet.

### 5. Raise the recents cap

Change `LIMIT 20` (`FavoriteStore.swift:343`) to **50**. The limit applies *after* dedupe, so raising it is monotone and changes no dedupe semantics. Recents reload on `.startup`, `.setAppState(.active)`, and every `.addMealEntry`/`.deleteMealEntry` (`:71-76`), so nothing else needs touching.

## Tests

There is **no test anywhere** referencing `recentMealEntries`, `getRecentMealEntries`, `FavoriteStore`, `filteredRecents`, or `.searchable`, and **no middleware/GRDB test harness exists**. So:

- [ ] **Reducer pair**, copied from `DOSBTSTests/DirectReducerTests.swift:634-657`: (a) `setMealHistoryResults` stores results and `nil` clears them; (b) the state is transient — construct a fresh `AppState` from the same defaults and assert it is `nil`. Use `makeTestDefaults()` (`DirectReducerTests.swift:15-22`) — **never** bare `AppState()`.
- [ ] **Pure merge/dedupe model + tests.** Extract the "recents + DB hits → displayed rows" logic into a testable struct, following `HypoFilteredEntryModel` (`UnifiedFoodEntryView.swift:8-25` + `DOSBTSTests/HypoFilteredEntryTests.swift`) as the in-file-pure-model precedent. Cover: dedupe is case-insensitive, recents win over DB duplicates, stale-query results are rejected, below-threshold queries use the in-memory path.

**Adding a new test file requires four manual `project.pbxproj` edits** (that group is a classic `PBXGroup`, unlike the auto-synced `App/`/`Library/`/`Widgets/`): `PBXBuildFile` (block ends ~`:80`), `PBXFileReference` (after `:160`), group children (after `:330`), `PBXSourcesBuildPhase` (after `:552`). Copy the shape of `InsulinBatchBuilderTests`. Next free id pair: **`TE0100010000002800A00028`** / **`TE0100020000002800A00028`**. PBXBuildFile and PBXFileReference rows use 2 tabs; group-children and build-phase rows use 4. Finish with `plutil -lint DOSBTS.xcodeproj/project.pbxproj`.

## Must not change

- `MealItemRow`'s `.recent` variant. `DOSBTSTests/MealItemRowTests.swift:38` pins `#expect(model.timestampLabel == nil)` — adding a timestamp to `.recent` **fails that test**. If search results need a date, add a *third* variant rather than editing `.recent`. (V1: no timestamp — keep the diff small.)
- `HypoFilteredEntryModel` decisions (`DOSBTSTests/HypoFilteredEntryTests.swift:15-45` pins the no-dead-end guarantee). Note `actionsSection` only renders when `!filterToHypoTreatments` (`:79-81`) — decide the same for the search section, and if hypo-filtered mode gains search, extend the pure model rather than adding an untested `if` in the view.
- The dedupe semantics of `getRecentMealEntries`.
- Relog hydration (`MealEntry.toNutritionEstimate`) — a months-old hit may have an `analysisSessionId` whose `PersonalFood` rows were pruned; the aggregate fallback is already pinned by `DOSBTSTests/MealEntryRelogTests.swift:87, :104`. Don't touch it.

## Verification

```bash
xcodebuild test -project DOSBTS.xcodeproj -scheme DOSBTSApp \
  -destination 'id=9A948885-80C7-4A96-A9FB-D2742595AD3B'
```

That UDID is **iPhone 17 Pro / iOS 26.5**. Device names repeat across three runtimes — always target by `id=`.

**On-simulator:**
1. Log ≥25 distinct foods (vary the names). Confirm the oldest is no longer in the RECENT list.
2. Type ≥3 chars of that oldest food's name → **it appears**. This is the whole point of the change.
3. Tap it → staging plate opens with the food hydrated. Hold it → logs immediately.
4. Type fast (`a`→`ap`→`app`→`appl`) → results settle on the final query; no flicker of wrong rows.
5. Clear the query → returns to the plain recents list, no stale rows.
6. Search with no matches anywhere → the empty state reads sensibly (not a spinner).

## Out of scope

- Lane A2 entirely: `PersonalFood` catalog promotion, macro columns, `source`/`useCount`, upsert-from-every-path, prune relaxation, per-food portion presets ("chunks").
- Voice/mic (DMNC-1486) — **it will add a mic to this same search field later**, so keep this change surgical around `filteredRecents` and the RECENT section, and do not restructure the view.
- Fuzzy matching, ranking by frequency, search history, or highlighting matched substrings (the last one would break `MealItemRowTests.swift:72,75`, which pins that the model never clips the name).
