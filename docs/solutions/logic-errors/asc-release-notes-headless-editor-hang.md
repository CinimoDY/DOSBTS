---
title: Headless deploy hangs forever — release-notes editor blocks on no TTY, piped output hides it
date: 2026-07-18
category: logic-errors
module: deploy-pipeline
problem_type: logic_error
component: tooling
symptoms:
  - "`deploy.sh` hangs after a successful TestFlight upload with zero visible output — `ps` reveals a stuck `vi` on the notes tempfile"
  - "Standalone re-run of `scripts/asc-release-notes.sh` stalls the same way when run headless (stdin /dev/null, no TTY)"
  - "Piping the deploy through `tail` hides all progress, so the hang is silent and easy to misread as an upload failure"
root_cause: missing_validation
resolution_type: code_fix
severity: medium
related_components:
  - development_workflow
tags: [deploy, testflight, asc-api, shell-script, tty-guard, headless, editor-hang, release-notes]
---

# Headless deploy hangs forever — release-notes editor blocks on no TTY, piped output hides it

## Problem

`deploy.sh` finishes its archive and TestFlight upload, then runs `scripts/asc-release-notes.sh` to derive the build's "What to Test" from `CHANGELOG.md` and push it via the App Store Connect API (`deploy.sh:88-91`). Before the TTY guard existed, that script *unconditionally* built a review scaffold and opened it in an editor — `"${EDITOR:-vi}" "$TMP_NOTES"` (now at `scripts/asc-release-notes.sh:119`).

Run `./deploy.sh` from an agent session — stdin is `/dev/null`, no TTY — and `vi` blocks forever waiting for a terminal that will never answer. Worse, the deploy in question (Build 132, 2026-07-18) was run in a background shell with output piped through `tail -40`. `tail` buffers until EOF, so *nothing* was printed while the process hung: no "==> Review the TestFlight notes" line, no error, no prompt. The deploy simply never returned, with zero visible evidence of why.

Two failure ingredients compound here, and each hides the other:

1. **An interactive step in a headless pipeline** — `vi` on a `/dev/null` stdin blocks indefinitely; the script had no timeout around the editor invocation.
2. **Buffered/piped output** — piping a long-running script through `tail` (or anything that waits for EOF) means you can't distinguish "hung on an editor" from "legitimately polling App Store Connect" (the build-registration poll alone can run ~15 minutes: 30 × 30 s at `scripts/asc-release-notes.sh:168-205`, and the VALID-state wait another ~30 minutes at `:293-317`).

## Symptoms

- `./deploy.sh` prints archive/upload progress (or nothing at all, if piped), reaches the upload successfully, then never returns — no error, no timeout, no further output.
- Piping through `tail -40` (or similar) shows nothing while the hang is in progress; output only flushes on process exit, which never comes.
- `ps aux | grep -E 'deploy|asc-release|vi'` reveals the stuck chain: `deploy.sh` → `asc-release-notes.sh` → `vi /var/folders/.../asc-notes.XXXX`. This was the only way the hang was diagnosed.
- A killed-and-retried standalone run of `scripts/asc-release-notes.sh` *also* appears to hang if its output is piped, because the legitimate ASC polling (silent 30 s sleeps) is indistinguishable from a block.

## What Didn't Work

- **Waiting it out.** There is no timeout around the editor invocation — `vi` on a non-TTY stdin blocks unboundedly. The script's timeouts all live *after* the editor step (build-registration poll, VALID wait); none of them can rescue a pre-poll hang.
- **Kill and re-run standalone, still piped.** The re-run — with `EDITOR` pointed at a scripted rewrite — was killed by a 5-minute shell timeout and *also* looked hung. Post-mortem it was ambiguous whether it was blocked again or just inside the legitimate up-to-15-minute ASC registration poll (`scripts/asc-release-notes.sh:168-205`), because the piped output hid the `==> Waiting for our just-uploaded build to register...` progress line. Lesson: never pipe a long-running, possibly-interactive script through a buffering consumer — run it with output going straight to the terminal (or `tee` to a log) so you can see *which* phase it is in.
- **Panicking about the deploy** — unnecessary, and worth knowing before you touch anything. The upload had already completed (`deploy.sh:74-82` runs the `xcodebuild -exportArchive` upload *before* the notes step), and the notes step is deliberately fail-soft: `deploy.sh:90-91` wraps it in a subshell with `|| echo "WARN: notes push failed; upload intact — re-run ./scripts/asc-release-notes.sh"`. A hang or failure after the upload is **never a lost deploy** — the build is on TestFlight; only the "What to Test" text is missing, and it is re-pushable at any time.

## Solution

Two parts: the immediate recovery (push the notes directly via the ASC API) and the durable fix (a TTY guard in the script).

### Recovery: push "What to Test" directly via the ASC API

When the script is wedged or you just want the notes up *now*, ~50 lines of Python against the ASC API does it. Credentials are the same ones `deploy.sh` exports (`deploy.sh:15-17`), plus `ASC_APP_ID`; JWTs are minted by the existing `scripts/asc-jwt.py <key_path> <key_id> <issuer_id> [exp_seconds]` shim (`scripts/asc-jwt.py:9`).

```python
#!/usr/bin/env python3
"""Recovery: set a TestFlight build's 'What to Test' directly via the ASC API."""
import json, os, subprocess, urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
APP_ID = os.environ["ASC_APP_ID"]
EXPECTED_BUILD = "132"                              # the build you just uploaded
NOTES = open("notes.txt", encoding="utf-8").read()
assert len(NOTES) <= 4000, f"{len(NOTES)} chars — ASC caps whatsNew at 4000"

def jwt():
    return subprocess.run(
        ["python3", "scripts/asc-jwt.py", os.environ["ASC_KEY_PATH"],
         os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], "300"],
        capture_output=True, text=True, check=True).stdout.strip()

def call(method, url, body=None):
    req = urllib.request.Request(url, method=method,
        headers={"Authorization": f"Bearer {jwt()}",
                 "Content-Type": "application/json"},
        data=json.dumps(body).encode() if body else None)
    with urllib.request.urlopen(req) as r:
        return json.load(r)

# 1. Newest build for the app — assert it is the one we mean before writing.
b = call("GET", f"{API}/builds?filter%5Bapp%5D={APP_ID}&sort=-uploadedDate&limit=1")["data"][0]
assert b["attributes"]["version"] == EXPECTED_BUILD, (
    f"newest ASC build is {b['attributes']['version']}, not {EXPECTED_BUILD} — refusing to write")
build_id = b["id"]

# 2. Find the en-US localization for that build.
locs = call("GET", f"{API}/builds/{build_id}/betaBuildLocalizations")["data"]
loc_id = next(x["id"] for x in locs if x["attributes"]["locale"] == "en-US")

# 3. PATCH whatsNew.
call("PATCH", f"{API}/betaBuildLocalizations/{loc_id}",
     {"data": {"id": loc_id, "type": "betaBuildLocalizations",
               "attributes": {"whatsNew": NOTES}}})

# 4. Read it back to verify.
locs = call("GET", f"{API}/builds/{build_id}/betaBuildLocalizations")["data"]
print(next(x["attributes"]["whatsNew"] for x in locs if x["id"] == loc_id))
```

Notes on the recipe:

- The version assertion in step 1 is the safety rail — never PATCH whatever happens to be newest without confirming it is your build.
- If no `en-US` localization exists yet, POST one instead (body shape as in `scripts/asc-release-notes.sh:256-265`: `{"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": ...}, "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}}`).
- If the build is still processing, the PATCH can be rejected with a processing-state error; wait for `processingState == "VALID"` and retry (the shell script's own handling: `scripts/asc-release-notes.sh:293-317`).
- `whatsNew` is capped at 4000 *characters* — count characters, not bytes; the DOS-styled notes are em-dash/bullet heavy at 3 UTF-8 bytes each (`scripts/asc-release-notes.sh:129-132`).

Alternatively, once the terminal is sane, the script itself is the re-run path: `ASC_BUILD_NUMBER=132 ./scripts/asc-release-notes.sh` targets the build directly, ignoring the 30-minute recency window (`scripts/asc-release-notes.sh:47`); or widen the window with `MAX_BUILD_AGE` (`:44`).

### Durable fix: TTY guard around the scaffold + editor step

The fix in `scripts/asc-release-notes.sh:110-123` makes the interactive review conditional on someone actually being able to review:

```bash
if [ -t 0 ] || [ -n "${EDITOR:-}" ]; then
  # scaffold (FOCUS THIS BUILD / KNOWN ISSUES placeholders) + "${EDITOR:-vi}" review
else
  printf '%s\n' "$NOTES_BODY" > "$TMP_NOTES"
  echo "==> No TTY and no EDITOR: skipping review, pushing changelog-derived notes without the scaffold."
fi
```

Three branches:

1. **stdin is a TTY** (`[ -t 0 ]`) — interactive as before: scaffold plus `${EDITOR:-vi}` review (`:111-119`).
2. **No TTY but `EDITOR` is explicitly set** — still run it. This supports scripted non-interactive curation: an agent can set `EDITOR` to a script that rewrites the FOCUS/KNOWN ISSUES sections and exits, and the pipeline stays fully headless.
3. **No TTY and no `EDITOR`** — skip review entirely and push *only* the changelog-derived notes body, **without the scaffold** (`:120-122`). The scaffold's `(edit or delete)` placeholder lines (`:114-116`) exist solely for a human/scripted editor to resolve; unreviewed, they must never reach testers.

## Why This Works

- `[ -t 0 ]` is the standard, reliable test for "is a human attached": it is true in a normal terminal run and false under `/dev/null` stdin, cron, CI, and agent-driven background shells. The guard turns "block forever" into an explicit, logged decision.
- Treating an explicitly-set `EDITOR` as consent to run it preserves both workflows: humans keep the review gate; automation gets a hook to curate notes without a TTY. Only the truly-unattended case auto-pushes, and it pushes content that is safe by construction (the cleaned changelog block, which is exactly what ships in the in-app What's New — no placeholders).
- The recovery path works because the notes step was *designed* to be decoupled from the upload: `deploy.sh` runs it fail-soft after the upload (`deploy.sh:88-91`), and the "What to Test" field is just a `betaBuildLocalizations` resource that can be written any number of times after the fact. Nothing about a post-upload hang is time-critical or unrecoverable.

## Prevention

- **The TTY guard itself** (`scripts/asc-release-notes.sh:110-123`) — the in-file comment at `:108-109` records the incident ("bit us twice on Build 132"). Any future script that opens an editor, prompts, or reads stdin must carry the same `[ -t 0 ]` guard before assuming a human is present.
- **Never pipe a long-running deploy through a buffering consumer.** `./deploy.sh | tail -40` hid a 100%-diagnosable hang. Run it with output attached to the terminal, or `./deploy.sh 2>&1 | tee /tmp/deploy.log` if you need capture — `tee` flushes line-by-line, so you always see the last phase reached.
- **`ps aux | grep -E 'deploy|asc-release|vi|xcodebuild'` is the first diagnostic** when a deploy "never returns" after the upload line. It immediately distinguishes an editor block from an ASC poll (`sleep 30` loops) from a wedged `xcodebuild`.
- **Know the failure boundary: a hang or failure after "Uploading to TestFlight" succeeds is never a lost deploy.** The notes step is fail-soft and independently re-runnable (`deploy.sh:90-91`); kill the stuck process without fear and re-push notes via `ASC_BUILD_NUMBER=<n> ./scripts/asc-release-notes.sh` or the direct-API recipe above.

## Related Issues

- [ASC auto-managed build numbers drift](../best-practices/asc-auto-managed-build-numbers-drift-20260621.md) — same pipeline and script, different failure mode; documents the `whatsNew` field fact and recency-matching behavior the recovery recipe builds on.
- [Changelog metadata-strip grammar parity](../best-practices/dual-implementation-text-grammar-parity-20260620.md) — the perl cleaning stage that produces the notes body the headless path now pushes unreviewed.
- Issue tracking lives in Linear (DMNC-*); GitHub issues are disabled for this repo.
