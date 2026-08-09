# Implementation notes

Newest entry on top. Decisions and observations that were not spelled out in the
brief or plan, recorded so the next reader doesn't have to re-derive them.

## 2026-08-09 — Journal notes V1 review hardening (DMNC-1485, PR #114)

### Decisions taken beyond the literal brief

**1. The AI-consent Settings section gate had to be widened, or the consent bump
would have been a trap.** `AISettingsView` showed its "AI consent" section only
`if aiConsentFoodPhoto || aiConsentDailyDigest`, and that section holds the only
dispatch site for the Daily Insights toggle in the whole app. Bumping the key to
`aiConsentDailyDigestV2` flips previously-consented users to `false` — so a user
who had digest consent but *not* food-photo consent would have lost the section
and had no way to re-affirm. Gate is now
`claudeAPIKeyValid || aiConsentFoodPhoto || aiConsentDailyDigestV2`. Anyone who
ever used the digest AI necessarily has a validated key, so this reaches exactly
the affected population without exposing the toggle to users who have no key.

**2. Prior insights now replay as their headline, not raw stored JSON.** Adding
`{`, `}` and `"` to the escaped set (brief item 1a) has a side effect the brief
didn't mention: `<recent_days>` replays `past.aiInsight` through the same
sanitizer, and that stored string *is* a JSON insight object. Escaped verbatim it
becomes `&lbrace;&quot;headline&quot;…`, which burns most of the 200-char budget
on entities. Rather than accept that regression, the replay now uses
`DigestInsight.parse(insight)?.headline ?? insight`. This is also strictly safer:
it closes the second half of the forging vector the review identified (forge an
insight once via a note, get it echoed as *structure* into the next seven days'
prompts). Legacy plain-text insights don't parse and fall through unchanged —
pinned by `legacyPriorInsightStillReplays`.

**3. `shouldRefreshDigestEvents` extracted as an internal pure function.** The
day-match guard for the note→digest-events refresh (brief item 4) would otherwise
have lived inside a `private` free function calling `DataStore.shared`, i.e. only
reachable with a live database. Extracting the predicate keeps the guard covered
by `JournalNoteDigestRefreshTests` without a DB.

### Observations / accepted residuals

**Legacy consent key is left completely untouched — including on revoke.** Per
the brief, `libre-direct.settings.ai-consent-daily-digest` is never read *or
written* by the new code. The nuance that buys: if a user revokes consent on this
build and the build is then rolled back, the old build reads the old key and
finds consent still `true`. Clearing the legacy key on revoke would close that,
but it contradicts the brief's "leave the old key in place, unread, so a rollback
still works". Flagging for the orchestrator rather than deciding unilaterally.

**One residual AI-call trigger survives the `!dailyDigestInsightLoading` guard.**
If a generation *failed* (`dailyDigestInsightLoading == false`, `aiInsight` still
nil) and the user then adds notes, each note's events refresh re-enters the
`.setDailyDigestEvents` branch and fires one retry. This is bounded by the user's
note-adding rate, only occurs after a prior failure, and reads as a reasonable
retry — but it is a paid call per note, so it is worth knowing about. Eliminating
it entirely would require distinguishing the refresh's origin (a `source` on
`.setDailyDigestEvents`), which ripples further than this hardening pass.

**`carriageReturnIsFlattened` and `legacyPriorInsightStillReplays` pass against
the pre-fix code.** The old sanitizer already handled `\r` explicitly, so that
test is a regression guard for the rewrite rather than proof of a fixed bug. The
other seven new prompt tests were verified to fail against pre-fix
`ClaudeService.swift` (`git show HEAD:` restore, targeted `-only-testing` run).

**No live-DB coverage for the store queries.** `getDailyEvents`' day bounds and
the `id` ordering tiebreaker are SQL; `JournalNoteDayBoundsTests` pins the
half-open `[startOfDay, nextDay.startOfDay)` *convention* in Swift, which guards
the intent but does not execute the query. Verifying the tiebreaker and the
degrade-to-empty notes `catch` needs on-device/simulator exercise.
