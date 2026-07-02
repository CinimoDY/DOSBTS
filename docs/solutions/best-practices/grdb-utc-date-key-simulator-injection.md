---
title: "GRDB date keys are UTC ISO8601: use timezone-aware startOfDay when injecting test records"
date: 2026-07-02
category: best-practices
module: testing/simulator tooling
problem_type: developer_experience
component: DailyDigestMiddleware
severity: medium
applies_when:
  - "Injecting GRDB records that are looked up by a date key (DailyDigest, future date-keyed models)"
  - "A manually inserted row is never returned by the app's cache lookup even though sqlite3 confirms the row exists"
  - "An INSERT fails with UNIQUE constraint on a date column that looks unoccupied"
tags: [grdb, simulator, sqlite, timezone, dailydigest, date, utc, testing]
---

# GRDB date keys are UTC ISO8601: use timezone-aware startOfDay when injecting test records

## Context

When injecting a `DailyDigest` row into the simulator GRDB database for screenshot or repro work, inserting with a bare date string like `'2026-07-01'` produces either a silent cache miss or a UNIQUE constraint failure — even though `sqlite3 ... "SELECT * FROM DailyDigest"` shows the row was written. The mismatch is invisible until you compare the stored date value with what the app actually queries.

## Guidance

GRDB stores all `Date` values as UTC ISO8601 text. The `DailyDigestMiddleware` past-day cache lookup calls `Calendar.current.startOfDay(for: date)` — a **timezone-aware** call that returns local midnight expressed in UTC.

For CEST (UTC+2), **July 1 CEST midnight = `2026-06-30 22:00:00.000` UTC**. If you insert a row with `date = '2026-07-01'` and the existing computed record sits at `'2026-06-30 22:00:00.000'`, the lookup misses and the middleware recomputes from scratch (or fails with UNIQUE on the next insert).

**Correct injection workflow:**

1. Query the existing date key first (never guess):

   ```bash
   sqlite3 "$DB" "SELECT id, date FROM DailyDigest ORDER BY date DESC LIMIT 5;"
   ```

2. UPDATE in-place rather than INSERT — the middleware has already computed a row for recent past days:

   ```bash
   sqlite3 "$DB" "UPDATE DailyDigest SET aiInsight = '...json...' WHERE date = '2026-06-30 22:00:00.000';"
   ```

3. If you need a new row for a date that was never computed, derive the UTC key in Python:

   ```python
   from datetime import datetime, timezone
   import pytz

   tz = pytz.timezone('Europe/Berlin')  # match device timezone
   local_date = datetime(2026, 7, 1, tzinfo=tz)
   utc_key = local_date.replace(hour=0, minute=0, second=0, microsecond=0).astimezone(timezone.utc)
   print(utc_key.strftime('%Y-%m-%d %H:%M:%S.000'))  # → 2026-06-30 22:00:00.000
   ```

**Today always recomputes.** The past-day cache path only applies to dates before today. `DailyDigestMiddleware` unconditionally recomputes the current day regardless of what is in the database, so injecting a row for today's UTC key has no effect on what the app displays.

## Why This Matters

The bug is silent in both directions: the INSERT appears to succeed (sqlite3 shows the row), and the cache miss causes the middleware to fall back to live computation rather than erroring. The only signal is that your injected `aiInsight` never appears on screen.

The UNIQUE constraint failure mode is equally confusing — `sqlite3 ... "SELECT COUNT(*) FROM DailyDigest WHERE date = '2026-07-01'"` returns 0, yet the INSERT fails. The existing row sits at the timezone-adjusted key and only appears when you SELECT without a WHERE clause.

## When to Apply

Any time you inject rows into a GRDB model that uses `Date` as a primary or unique key and where the app looks up rows via a timezone-aware `startOfDay` or `endOfDay` call — currently `DailyDigest`, potentially future per-day aggregations.

The plain GRDB read/write path (non-date keys, or keys derived from `Date.timeIntervalSince1970`) is not affected.

## Examples

**Full inject-and-verify sequence used for DMNC-1226 screenshot work:**

```bash
DB=/path/to/GlucoseDirect.sqlite

# 1. Find the existing July 1 CEST record
sqlite3 "$DB" "SELECT date, avg, tir FROM DailyDigest ORDER BY date DESC LIMIT 5;"
# → 2026-06-30 22:00:00.000  (this is July 1 CEST)

# 2. Update in-place with hand-crafted AI insight JSON
INSIGHT='{"headline":"Solid control","grade":"mixed","facts":[{"label":"TIR","value":"71%","tone":"good"}],"tips":["Breakfast spike — try 15 min pre-bolus"],"cheer":"Good work!"}'
sqlite3 "$DB" "UPDATE DailyDigest SET aiInsight = '$INSIGHT' WHERE date = '2026-06-30 22:00:00.000';"

# 3. Verify
sqlite3 "$DB" "SELECT date, aiInsight FROM DailyDigest WHERE date = '2026-06-30 22:00:00.000';"
```
