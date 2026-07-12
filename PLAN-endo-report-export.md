# PLAN: Endo-visit report export — clinic-ready summary (PDF + CSV)

**Linear:** DMNC-1304 (Backlog → In Progress).
**Rank:** 4 of 6. Effort: L (~1.5–2 days). Independent of the Ratio Lab plans.

## Goal

A "CLINIC REPORT" screen that generates a clinician-readable summary over a selectable period (14 / 30 / 90 days) and shares it via the system share sheet:

- **PDF** (primary): DOS-styled but print-legible — header (period, generated date, app build), core stats (AVG, SD, CV, GMI, readings count), consensus TIR bars (TIR/TBR/TAR), hourly daily-pattern table (24 rows: median + P25–P75 per hour), event counts (meals, boluses by type, basal entries, hypo episodes).
- **CSV** (fallback): the same summary as rows, using the repo's existing CSV machinery.

Explicitly NOT in v1: the full AGP percentile-band *chart* (deferred — the hourly table carries the same information in v1), Nightscout/HealthKit provider sync.

## Preconditions

1. `git pull --ff-only`; branch `claude/dmnc-1304`.
2. Read fully before coding: `App/Modules/DataStore/StoreExport.swift` (existing CSV export: `createFile`/`writeFile` helpers, `storeExportMiddleware`, paged reads), `App/Modules/DataStore/SensorGlucoseStore.swift:232` (`getSensorGlucoseStatistics(days:lowerLimit:upperLimit:)` — stats are ALREADY computed in SQL), `App/Modules/Log/Log.swift:85-110` (the `.sendFile` → `UIActivityViewController` share path), `App/Views/Settings/InsulinCategoryView.swift` (the "Ratios" NavigationLink row pattern to copy), `Library/Content/SensorGlucose.swift:14-41` (`GlucoseStatistics`).

## Massive reuse — do not rebuild these

| Need | Existing asset |
|---|---|
| Period stats (avg/gmi/tbr/tar/variance/readings/days) | `DataStore.getSensorGlucoseStatistics(days:lowerLimit:upperLimit:)` returns `GlucoseStatistics`; `tir`, `cv`, `stdev` are computed properties |
| CSV file creation + escaping | `createFile(filename:)` + `writeFile(temporaryURL:values:)` in `StoreExport.swift` (incl. `escapeCSVField`) |
| Share sheet | dispatch `.sendFile(fileURL:)` — `Library/DirectAction.swift:66`; the Log middleware's `SendService` presents `UIActivityViewController` correctly (App-side, iOS-26-safe scene lookup) |
| Middleware→file→share flow shape | `storeExportMiddleware`'s `.exportToUnknown` case is the template: background queue → build file → `promise(.success(.sendFile(fileURL:)))` |
| mmol/L formatting | `.asGlucose(glucoseUnit:)` + the `mmolLFormatter` pattern in StoreExport |

## Exact files to touch

| File | Change |
|---|---|
| `Library/Content/ClinicReport.swift` | NEW — pure report model + builder (`ClinicReportData`, `ReportPeriod` enum 14/30/90, hourly-pattern + event-count computation from raw arrays) |
| `App/Modules/DataStore/ClinicReportStore.swift` | NEW — `getClinicReportData(days:)`: ONE `asyncRead` fetching readings + meals + insulin + treatment/exercise counts for the period |
| `App/Modules/Report/ClinicReportMiddleware.swift` | NEW — `.generateClinicReport(period:format:)` → fetch → render PDF or write CSV → `.sendFile(fileURL:)` |
| `App/Views/Settings/ClinicReportView.swift` | NEW — period picker (3 `AmberChip`s), format buttons (`EXPORT PDF` / `EXPORT CSV`), preview summary card |
| `App/Views/Settings/GlucoseDisplayCategoryView.swift` | Add `NavigationLink` row "Clinic Report" (mirror the Ratios row in `InsulinCategoryView.swift`: icon `doc.text`, `SettingsHubRow` if that's the row component) |
| `Library/DirectAction.swift` | Add `case generateClinicReport(days: Int, format: ClinicReportFormat)` |
| `App/App.swift` | Register `clinicReportMiddleware()` in **BOTH** middleware arrays |
| `DOSBTSTests/` | Builder tests — extend an existing file OR register a new one in pbxproj (see traps) |
| `CHANGELOG.md` | `Added` — DMNC-1304 |

Reducer: `.generateClinicReport` needs a reducer case that does nothing (`break`) — check how `.exportToUnknown` is handled in `DirectReducer.swift` and mirror it exactly (pure-trigger actions fall through).

## Implementation steps (in order)

1. **`Library/Content/ClinicReport.swift`** — pure types + math, fully testable without a DB:
   ```swift
   enum ClinicReportFormat { case pdf, csv }
   struct HourlyPattern: Equatable { let hour: Int; let median: Int?; let p25: Int?; let p75: Int?; let readings: Int }
   struct ClinicReportData { let statistics: GlucoseStatistics; let hourlyPatterns: [HourlyPattern]  // always 24 entries
                             let mealCount: Int; let bolusCounts: [InsulinType: Int]; let basalCount: Int
                             let hypoEpisodeCount: Int; let period: DateInterval }
   enum ClinicReportBuilder { static func hourlyPatterns(from readings: [SensorGlucose]) -> [HourlyPattern]
                              static func hypoEpisodes(from readings: [SensorGlucose]) -> Int }
   ```
   Hypo episode definition (decided): a maximal run of consecutive readings `< 70 mg/dL` lasting ≥ 15 min; runs separated by ≥ 30 min in range count separately.
2. **`ClinicReportStore.swift`** — follow the `getRatioEvidence` shape (extension on `DataStore`, one `asyncRead`, promise return, `.failure` on error). Fetch: `SensorGlucose` in period, `MealEntry` count, `InsulinDelivery` in period (type counts in Swift — `InsulinType` is Codable, not SQL-filterable), and call the existing `getSensorGlucoseStatistics` SQL separately from the middleware (it's its own Future — combine with `zip` in the middleware, or fold the stats query into the new asyncRead by replicating its SQL; **decided: call both Futures and `Publishers.Zip` them in the middleware** — no SQL duplication).
3. **`ClinicReportMiddleware.swift`** — on `.generateClinicReport(days:format:)`:
   - `guard state.appState == .active`.
   - Zip `getClinicReportData(days:)` + `getSensorGlucoseStatistics(days: days, lowerLimit: 70, upperLimit: 180)` → build `ClinicReportData`.
   - `format == .csv`: reuse `createFile(filename: "dosbts-clinic-report")` + `writeFile` — sections as labeled rows (STATISTICS block, HOURLY PATTERN block, EVENTS block), both mg/dL and mmol/L columns like the existing export.
   - `format == .pdf`: render on the **MainActor** (see trap 4) via `ImageRenderer` into a `CGContext` PDF (`CGContext(url as CFURL, mediaBox: &box, nil)`, `beginPDFPage`/`endPDFPage`/`closePDF`), A4 page box (595×842 pt). Write to the Documents dir like `createFile` does (`.pdf` extension).
   - Emit `.sendFile(fileURL:)` — the existing Log middleware handles presentation; do NOT present a share sheet from the new middleware or view.
4. **PDF page view** (inside `ClinicReportView.swift` or a sibling `ClinicReportPage.swift` under `App/Views/Settings/`): a fixed-size SwiftUI layout sized for A4. DOS aesthetic but print-aware: **white background for print** is BANNED by the design system ("no real white") — decided: keep the terminal look (black bg, amber text) exactly like the app; clinics print fine from dark PDFs and it is the product's identity. Use `AmberTheme`/`DOSTypography` tokens only.
5. **`ClinicReportView.swift`** — ScrollView (copy RatioLabView's chrome: `.background(AmberTheme.dosBlack)`, `.dosNavigationTitle("Clinic Report")`), period chips (14/30/90 DAYS), a live preview card of the headline stats for the selected period (dispatch a load on appear or reuse the report data action with a `.setClinicReportPreview`—**decided: keep v1 simple, no preview state: the screen shows period picker + two export buttons + explainer/disclaimer text only**), buttons dispatch `.generateClinicReport`.
6. **Entry row** in `GlucoseDisplayCategoryView.swift`.
7. **Tests**: `ClinicReportBuilder` — hourly bucketing (readings at 23:59/00:01 land in different buckets; empty hours → nil median, 24 entries ALWAYS), median/percentile math odd+even, hypo-episode run-splitting (two dips separated by 40 min in range = 2 episodes; a 10-min dip = 0), event counting by `InsulinType`.
8. Build both targets, suite, CHANGELOG, PR.

## Cases a weaker model would miss

1. **TIR bands are clinical consensus, NOT the user's alarm thresholds.** Call `getSensorGlucoseStatistics(days:, lowerLimit: 70, upperLimit: 180)` with literal 70/180 (international consensus TIR) — do NOT pass `state.alarmLow/alarmHigh`. The user's alarm profile (day/night, e.g. 80/180) is a personal alerting preference; a clinician expects standard TIR or the report is non-comparable. Add one caption line to the PDF: `TIR BAND 70–180 MG/DL (CONSENSUS)`.
2. **`.sendFile` already exists — the share sheet is NOT your job.** Dispatch `.sendFile(fileURL:)` and stop. The Log middleware's `SendService` handles `UIActivityViewController` with the iOS-26-safe foreground-scene lookup. Building your own presenter duplicates `NS_EXTENSION_UNAVAILABLE`-sensitive code and risks the `UIApplication.shared`-outside-`App/` rule.
3. **Register the middleware in BOTH arrays in `App.swift`** (device + simulator). Missing the simulator array means the feature silently does nothing in every simulator test session — the repo has been bitten by this class before (documented in CLAUDE.md).
4. **`ImageRenderer` is MainActor-isolated.** The middleware runs its Future on a background queue for the DB work, but the PDF render step must hop to `MainActor` (e.g. `DispatchQueue.main.async` / `await MainActor.run`) before touching `ImageRenderer`, then hop back to fulfill the promise. Rendering off-main crashes or produces empty output.
5. **New Swift files under `App/` and `Library/` are auto-picked-up** (fileSystemSynchronized) — no pbxproj edits. But **test files are NOT**: a new `ClinicReportTests.swift` needs manual `DOSBTSTests` group + `PBXSourcesBuildPhase` entries per CLAUDE.md § Adding New Files. Alternative used by other plans: extend an existing test file — there is no natural host here, so follow the registration steps carefully and verify with a deliberately failing `#expect(false)` that the file actually RUNS before writing real tests (an unregistered test file passes silently by never executing).
6. **`Library/` compiles into the widget target.** `ClinicReport.swift` (pure model) is fine in `Library/Content/`, but anything touching `ImageRenderer`+UIKit-adjacent PDF contexts stays under `App/`. If the widget build breaks, you put rendering code in the wrong layer.
7. **The reducer must have a case (or explicit fallthrough) for the new action** — check how `.exportToUnknown` is treated in `DirectReducer.swift` and copy that exact pattern. If the reducer switch is exhaustive without `default`, a missing case is a compile error (good); if it has `default: break`, no reducer edit is needed at all.
8. **StyleGuard scans everything under `App/`** — the PDF page view included. No `.font(.system(...))`, no `Color.black` (use `AmberTheme.dosBlack`), no `cornerRadius`, no raw `Color(red:)`, no `.foregroundColor`. `Cmd+U` fails otherwise.
9. **Locale-stable dates for the clinic**: ISO-style `yyyy-MM-dd` via an explicit `DateFormatter` with fixed format (the StoreExport pattern) for CSV; the PDF header can use the same. Do not use `.formatted()` locale-floating output in the CSV — a German-locale export must not change column semantics.
10. **Period fetch bound**: 90 days at 1-min-rounded readings can be ~25–90k rows. Fetch once, ordered, in the single asyncRead (fine in memory), but do NOT fetch per-hour or per-day in a loop (N+1 reads on a serialized DatabaseQueue stalls the app — same lesson as the meal-impact loaders).
11. **Empty-data handling**: a fresh install with 3 readings must still produce a valid file (stats show what exists, hourly rows mostly `—`, counts zero) — never a crash or a zero-byte file. `getSensorGlucoseStatistics` may return degenerate values for near-empty sets; guard `readings > 0` before GMI/CV render and print `INSUFFICIENT DATA` under the stats block when `days < 14` of coverage (use `statistics.days`).
12. **Privacy**: no name/DOB fields — the report is intentionally pseudonymous (privacy-by-design rule); the clinician pairs it with the patient in person. Do not "helpfully" add patient-identity fields.

## Acceptance criteria

1. Both app + widget `xcodebuild ... build` succeed.
2. Suite green incl. new builder tests AND `StyleGuardTests`; verify the new test file executes (see trap 5) — test count in the log goes up.
3. Simulator (VirtualConnection, let it accumulate readings): Settings → Glucose & Display → Clinic Report; for each of 14/30/90: EXPORT PDF presents the share sheet with a non-empty PDF (save to Files, open, check header/stats/24-row table/events + the consensus-band caption); EXPORT CSV produces a parseable CSV (open, columns as spec'd, both units).
4. `grep -n "alarmLow\|alarmHigh" App/Modules/Report/ App/Modules/DataStore/ClinicReportStore.swift Library/Content/ClinicReport.swift` → no hits (trap 1 held).
5. Fresh-install run (erase simulator): generating a report does not crash; file renders with `INSUFFICIENT DATA` marker.
6. mmol/L unit setting: PDF glucose figures render in mmol/L (CSV always carries both columns).
7. CHANGELOG `[Unreleased]` `Added` entry ` — DMNC-1304`.

## Bookkeeping

Linear DMNC-1304 → In Progress / Done. Commit: `feat(report): clinic-visit summary export, PDF + CSV (DMNC-1304)`. Post-merge: consider `docs/solutions/` note on the ImageRenderer-PDF pattern (first PDF in the codebase — future features will want it).
