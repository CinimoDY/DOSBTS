---
title: "SQLite LIKE and COLLATE NOCASE fold ASCII only — non-ASCII food search silently misses, but only past the recents cap"
date: "2026-08-09"
category: logic-errors
module: "DataStore / food search"
problem_type: logic_error
component: data_layer
severity: high
applies_when:
  - "Adding a DB-backed search that must agree with an existing in-memory filter"
  - "Any GRDB query using LIKE or COLLATE NOCASE against user-authored text in a non-English locale"
  - "Deduping rows by a user-supplied name where case variants should collapse"
resolution_type: bug_fix
related_components:
  - grdb
  - search
tags:
  - sqlite
  - unicode
  - case-folding
  - grdb
  - search
  - localization
---

# SQLite LIKE and COLLATE NOCASE fold ASCII only

## Context

DMNC-1484 lane A1 added a DB-backed search so the Log Meal sheet could reach the whole `MealEntry` history instead of only the ~50 recents already in memory. The obvious implementation mirrors the in-memory filter with SQL:

```sql
WHERE m.mealDescription LIKE ? ESCAPE '\'   -- pattern = "%needle%"
  AND m.id = (SELECT m2.id FROM MealEntry m2
              WHERE m2.mealDescription = m.mealDescription COLLATE NOCASE
              ORDER BY m2.timestamp DESC LIMIT 1)
```

It passed tests, escaped `%`/`_`/backslash correctly, bound its parameters, and was wrong.

**SQLite's built-in `LIKE` and `COLLATE NOCASE` case-fold ASCII A–Z only.** Verified against the shipped SQL on a real simulator database:

```
SELECT ... WHERE mealDescription LIKE '%äpfel%' ESCAPE '\';   -- row 'Äpfel mit Zimt' → 0 ROWS
```

while in Swift, `"Äpfel mit Zimt".localizedCaseInsensitiveContains("äpfel")` is `true`.

Two symptoms, one root cause:

1. **Search misses.** Type `äpfel`, get nothing, for a food that demonstrably exists.
2. **Dedupe leaks.** `'MÜSLI'` and `'Müsli'` are *distinct* under `COLLATE NOCASE`, so both survive the SQL dedupe and each burns a slot of `LIMIT 50`, yielding fewer than 50 genuinely distinct foods.

## Why this is nastier than a plain miss

The in-memory path (`localizedCaseInsensitiveContains`) folds full Unicode; the SQL path does not. So a German food **works while it is inside the recents cap and silently stops working once it ages past it** — same query, same food, different answer depending on how long ago you last ate it. That is far harder for a user to report than a feature that never works, and it is the exact dead end the search was built to remove, now made intermittent instead of consistent.

The app ships 20+ localizations and its primary user logs German food. This would have shipped.

## Guidance

**Do not reach for `LIKE` when the goal is parity with a Swift-side filter.** Preferred fix, applied in `App/Modules/DataStore/FavoriteStore.swift`:

1. Run the dedupe query **unfiltered and unbounded** — one row per distinct name, newest wins.
2. Filter in Swift with the **same call the in-memory path uses** (`localizedCaseInsensitiveContains`).
3. Dedupe again in Swift on `.lowercased()` (full Unicode fold) **before** taking `limit`, so case variants that survived `COLLATE NOCASE` collapse instead of consuming slots.
4. Take `prefix(limit)`.

The two paths are then identical **by construction** rather than by careful maintenance. Bonus: no user text reaches SQL at all, so the `%`/`_`/backslash escaping code — and its `ESCAPE '\'` multiline-literal subtlety — is deleted outright, along with the injection surface.

The cost is materializing all distinct food names per search. At personal scale (one row per logged meal, deduped to a few hundred names) that is nothing, and the plan had already accepted a table scan because the composite index only accelerates prefix matching anyway.

If a future dataset makes the scan real, the fix is a folded shadow column (`mealDescriptionFolded`, written on insert) — **not** re-introducing `LIKE`. That would also enable `musli` → `Müsli`, which neither path does today.

## When to apply

Any time SQL and Swift both filter the same user-authored text and are expected to agree. Also check:

- `COLLATE NOCASE` used to collapse "the same" user-supplied name (dedupe, uniqueness, upsert keys) — it will not collapse non-ASCII case variants, so a "unique" name index can hold `Müsli` and `MÜSLI` side by side. Relevant to the `PersonalFood` catalog promotion in DMNC-1484 lane A2, whose unique NOCASE name index has exactly this property.
- `getRecentMealEntries` still dedupes with `COLLATE NOCASE` — deliberately left alone here because the plan pinned its semantics, so two case variants of a non-ASCII name can still each occupy a recents slot.

## Related

- [GRDB write inside asyncRead deadlock](grdb-write-inside-asyncread-deadlock-20260420.md) — the other rule every new store query has to satisfy.
- [GRDB Future with nil dbQueue hangs the subscriber](grdb-future-nil-dbqueue-hangs-subscriber-20260318.md) — the `if let dbQueue` form never fulfils its promise; use `guard let … else { promise(.success([])); return }`.
- [Middleware failure swallowed, nil-as-loading spins](middleware-failure-swallowed-nil-as-loading-spins-20260704.md) — why the search middleware needs a `.catch` that emits an empty result *for the current query*.
