#!/bin/bash
#
# asc-release-notes.sh — derive a TestFlight build's "What to Test" notes from
# CHANGELOG.md and push them via the App Store Connect API (DMNC-1147, U7).
#
# Called by deploy.sh after the upload, wrapped so it can never abort the
# deploy (fail-soft, re-runnable). Can also be run standalone after a deploy.
#
# Credentials come from the environment (no literals committed here):
#   ASC_KEY_PATH   path to the AuthKey_*.p8 private key
#   ASC_KEY_ID     the key id
#   ASC_ISSUER_ID  the issuer id
#   ASC_APP_ID     the numeric App Store Connect app id
# Optional: EDITOR (default vi), CHANGELOG (default CHANGELOG.md),
#           MAX_BUILD_AGE (recency window in seconds; default 1800 — widen for a late re-run),
#           ASC_BUILD_NUMBER (target a specific build number directly, ignoring recency — the
#                             robust path when running well after the deploy, e.g. 130).
#
set -euo pipefail

: "${ASC_KEY_PATH:?set ASC_KEY_PATH (path to AuthKey_*.p8)}"
: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
: "${ASC_APP_ID:?set ASC_APP_ID (numeric App Store Connect app id)}"

CHANGELOG="${CHANGELOG:-CHANGELOG.md}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JWT_TOOL="$SCRIPT_DIR/asc-jwt.py"
API="https://api.appstoreconnect.apple.com/v1"

# We identify the just-uploaded build by RECENCY, not by build number. App Store
# Connect can assign its own build number (auto-managed numbering, or a bump when
# the uploaded CFBundleVersion collides with an already-shipped build), so the
# ASC number may differ from the CHANGELOG's [Build N] — matching by number then
# silently misses. RUN_START is captured here, right after deploy.sh's upload and
# before the editor, so our build's uploadedDate sits within a short window of it;
# MAX_BUILD_AGE isolates our upload from any earlier deploy.
# Caveat: two deploys inside this window, with notes run before the 2nd registers,
# could match the 1st — re-run once the intended build is the newest.
RUN_START="$(date -u +%s)"
# Overridable so a standalone/late re-run can widen (or, via ASC_BUILD_NUMBER, ignore) the window.
MAX_BUILD_AGE="${MAX_BUILD_AGE:-1800}"  # 30 min default: covers upload->registration + clock skew, excludes prior deploys
# When set, target this exact build number and ignore recency — the robust path for a late
# standalone run (the newest build is accepted only when its version equals this).
ASC_BUILD_NUMBER="${ASC_BUILD_NUMBER:-}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found (needed for JWT signing + JSON)." >&2
  exit 1
fi
if ! command -v perl >/dev/null 2>&1; then
  echo "ERROR: perl not found (needed for changelog cleaning)." >&2
  exit 1
fi
if [ ! -f "$CHANGELOG" ]; then
  echo "ERROR: $CHANGELOG not found (run from the repo root)." >&2
  exit 1
fi

# --- temp files (mode 0600, always cleaned up) -----------------------------
TMP_NOTES="$(mktemp -t asc-notes)"
TMP_RESP="$(mktemp -t asc-resp)"
chmod 600 "$TMP_NOTES" "$TMP_RESP"
trap 'rm -f "$TMP_NOTES" "$TMP_RESP"' EXIT INT TERM

# --- 1. extract the latest [Build N] block (the shipping build) ------------
BLOCK="$(awk '
  /^## \[Build / { if (seen) exit; seen=1; print; next }
  seen && /^## /  { exit }
  seen            { print }
' "$CHANGELOG")"

if [ -z "$BLOCK" ]; then
  echo "ERROR: no '## [Build N]' block found in $CHANGELOG." >&2
  exit 1
fi

BUILD_NUMBER="$(printf '%s\n' "$BLOCK" | head -1 | sed -E 's/^## \[Build ([0-9]+).*/\1/')"
if ! printf '%s' "$BUILD_NUMBER" | grep -qE '^[0-9]+$'; then
  echo "ERROR: could not parse a build number from the latest block header." >&2
  exit 1
fi

# --- 2. clean → TestFlight notes ------------------------------------------
# Stage 1: strip {tour:} + trailing metadata via the shared KTD2 grammar
# (strip-changelog-metadata.pl — the single source of truth, twinned with
# Swift ChangelogParser and guarded by check-changelog-parity.sh).
# Stage 2: presentation only — reformat the build header, uppercase group
# headers, and bullet entries for the TestFlight field.
NOTES_BODY="$(printf '%s\n' "$BLOCK" \
  | perl "$SCRIPT_DIR/strip-changelog-metadata.pl" \
  | perl -CSD -pe '
  s/^## \[Build ([^\]]+)\][ \t]*\x{2014}[ \t]*(\S+).*$/BUILD $1 \x{2014} $2/;
  s/^###\s+(.*)$/\U$1/;
  s/^- /\x{2022} /;
')"

# --- 3. scaffold + review/edit (R14) ---------------------------------------
{
  printf '%s\n\n' "$NOTES_BODY"
  printf '%s\n' '--- FOCUS THIS BUILD ---'
  printf '%s\n\n' '(what testers should exercise in this build — edit or delete)'
  printf '%s\n' '--- KNOWN ISSUES ---'
  printf '%s\n' '(none — edit or delete)'
} > "$TMP_NOTES"

echo "==> Review the TestFlight notes for build $BUILD_NUMBER (saving closes the editor)..."
"${EDITOR:-vi}" "$TMP_NOTES"

# whatsNew (the API field behind TestFlight's "What to Test") has a 4000-CHARACTER
# ASC limit; warn but proceed (the API would
# 409). Count characters with perl, not `wc -c` (bytes) — the cleaned text is
# em-dash / bullet heavy (3 bytes each in UTF-8), so a byte count overcounts.
NOTE_LEN="$(perl -CSD -e 'local $/; my $s = <STDIN>; print length($s // "")' < "$TMP_NOTES")"
if [ "${NOTE_LEN:-0}" -gt 4000 ]; then
  echo "WARNING: notes are ${NOTE_LEN} chars; ASC caps 'What to Test' at 4000. Trim in the editor." >&2
fi

# --- JWT helper: mint a fresh short-lived token per call (never echoed) -----
mint_jwt() { python3 "$JWT_TOOL" "$ASC_KEY_PATH" "$ASC_KEY_ID" "$ASC_ISSUER_ID" 300; }

# Fail soft immediately on an auth/JWT problem (KTD8) — don't burn the poll.
if ! mint_jwt >/dev/null 2>"$TMP_RESP"; then
  echo "ERROR: JWT signing failed (check ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID):" >&2
  cat "$TMP_RESP" >&2
  exit 1
fi

# Mint into a local first: `Bearer $(mint_jwt)` in argument position would NOT
# abort on a mid-run signing failure (set -e is suppressed there) and would send
# an empty token, turning a 401 into a misleading poll timeout.
asc_get() {
  local jwt
  jwt="$(mint_jwt)" || { echo "ERROR: JWT signing failed mid-run." >&2; return 1; }
  curl -fsS -H "Authorization: Bearer $jwt" "$@"
}

# Extract a JSON value with python (stdin = response body).
json_get() { python3 -c "$1" 2>/dev/null || true; }

# --- 4. poll until our just-uploaded build registers in ASC (KTD8) ---------
# Newest build for the app, accepted only when uploaded within MAX_BUILD_AGE of
# this run (see RUN_START note). NB: /v1/builds does NOT support filter[platform]
# (ASC returns 400 PARAMETER_ERROR.INVALID) — filter by app only.
if [ -n "$ASC_BUILD_NUMBER" ]; then
  echo "==> Targeting build $ASC_BUILD_NUMBER directly (recency ignored); waiting for it to be the newest in App Store Connect (up to ~15 min)..."
else
  echo "==> Waiting for our just-uploaded build to register in App Store Connect (up to ~15 min)..."
fi
BUILD_QUERY="filter%5Bapp%5D=$ASC_APP_ID&sort=-uploadedDate&limit=1"
BUILD_ID=""
BUILD_VERSION=""
for _ in $(seq 1 30); do
  RESP="$(asc_get "$API/builds?$BUILD_QUERY" 2>/dev/null || true)"
  # Take the newest build, but only if its uploadedDate is recent enough to be
  # this deploy's — otherwise it's a prior deploy, so keep polling for ours to
  # register. Emits "id|version" so we can reconcile the notes header below.
  MATCH="$(printf '%s' "$RESP" | RUN_START="$RUN_START" MAX_AGE="$MAX_BUILD_AGE" WANT_VER="$ASC_BUILD_NUMBER" json_get '
import sys, json, os
from datetime import datetime
d = json.load(sys.stdin)
data = d.get("data") or []
if not data:
    print(""); raise SystemExit
b = data[0]
bid = b.get("id", "")
ver = (b.get("attributes") or {}).get("version") or ""
out = (bid + "|" + ver) if bid else ""
want = os.environ.get("WANT_VER") or ""
if want:
    # Direct target: accept the newest build only when it IS the requested number,
    # ignoring uploadedDate. Fails safe (keeps polling) if a different build is newest.
    print(out if ver == want else "")
    raise SystemExit
uploaded = (b.get("attributes") or {}).get("uploadedDate")
if not uploaded:
    print(out); raise SystemExit  # no date -> best effort, accept newest
try:
    ts = datetime.fromisoformat(uploaded.replace("Z", "+00:00")).timestamp()
except Exception:
    print(out); raise SystemExit
age = float(os.environ["RUN_START"]) - ts
print(out if age <= float(os.environ["MAX_AGE"]) else "")')"
  if [ -n "$MATCH" ]; then
    BUILD_ID="${MATCH%%|*}"
    BUILD_VERSION="${MATCH#*|}"
    break
  fi
  sleep 30
done

if [ -z "$BUILD_ID" ]; then
  if [ -n "$ASC_BUILD_NUMBER" ]; then
    echo "ERROR: build $ASC_BUILD_NUMBER did not appear as the newest in App Store Connect within the timeout." >&2
  else
    echo "ERROR: no recently-uploaded build registered in App Store Connect within the timeout. Re-run later." >&2
  fi
  exit 1
fi
echo "==> Found build ${BUILD_VERSION:-?} (id $BUILD_ID)."

# Reconcile the notes header with the ASC-assigned build number when it differs
# from the CHANGELOG's (e.g. ASC bumped it on a collision). Rewrites only the
# leading "BUILD <n>" token on the first line; any human edits are preserved.
if [ -n "$BUILD_VERSION" ] && [ "$BUILD_VERSION" != "$BUILD_NUMBER" ]; then
  echo "==> Note: ASC build number ($BUILD_VERSION) differs from CHANGELOG ($BUILD_NUMBER); using $BUILD_VERSION in the notes header." >&2
  OLD_NUM="$BUILD_NUMBER" NEW_NUM="$BUILD_VERSION" perl -CSD -i -pe 's/^BUILD \Q$ENV{OLD_NUM}\E\b/BUILD $ENV{NEW_NUM}/ if $. == 1' "$TMP_NOTES"
fi

# --- 5. find an existing en-US localization, then PATCH or POST ------------
# Re-resolvable so a retry after the VALID wait upgrades POST->PATCH if the
# first attempt (or ASC) created the localization in the meantime.
resolve_loc_id() {
  local resp
  resp="$(asc_get "$API/builds/$BUILD_ID/betaBuildLocalizations" 2>/dev/null || true)"
  printf '%s' "$resp" | json_get '
import sys, json
d = json.load(sys.stdin)
print(next((x["id"] for x in d.get("data", []) if x.get("attributes", {}).get("locale") == "en-US"), ""))'
}
LOC_ID="$(resolve_loc_id)"

write_notes() {
  # Build the JSON body in python (whatsNew passed via env, never via the
  # shell), and stream it to curl with --data-binary @-. Echoes the HTTP code.
  # Mint the token into a local first so a signing failure aborts the write
  # rather than sending an empty Bearer (see asc_get).
  local jwt
  jwt="$(mint_jwt)" || { echo "ERROR: JWT signing failed mid-run." >&2; return 1; }
  if [ -n "$LOC_ID" ]; then
    NOTES_FILE="$TMP_NOTES" LOC_ID="$LOC_ID" python3 -c '
import json, os
notes = open(os.environ["NOTES_FILE"], encoding="utf-8").read()
print(json.dumps({"data": {"type": "betaBuildLocalizations", "id": os.environ["LOC_ID"],
      "attributes": {"whatsNew": notes}}}))' \
    | curl -sS -X PATCH \
        -H "Authorization: Bearer $jwt" -H "Content-Type: application/json" \
        --data-binary @- -o "$TMP_RESP" -w '%{http_code}' \
        "$API/betaBuildLocalizations/$LOC_ID"
  else
    NOTES_FILE="$TMP_NOTES" BUILD_ID="$BUILD_ID" python3 -c '
import json, os
notes = open(os.environ["NOTES_FILE"], encoding="utf-8").read()
print(json.dumps({"data": {"type": "betaBuildLocalizations",
      "attributes": {"locale": "en-US", "whatsNew": notes},
      "relationships": {"build": {"data": {"type": "builds", "id": os.environ["BUILD_ID"]}}}}}))' \
    | curl -sS -X POST \
        -H "Authorization: Bearer $jwt" -H "Content-Type: application/json" \
        --data-binary @- -o "$TMP_RESP" -w '%{http_code}' \
        "$API/betaBuildLocalizations"
  fi
}

echo "==> Pushing 'What to Test' for build $BUILD_NUMBER..."
HTTP="$(write_notes)"

if [ "$HTTP" = "200" ] || [ "$HTTP" = "201" ]; then
  echo "==> Done. TestFlight 'What to Test' set for build $BUILD_NUMBER."
  exit 0
fi

# Auth/permission failures never resolve by waiting (KTD8: fail fast).
if [ "$HTTP" = "401" ] || [ "$HTTP" = "403" ]; then
  echo "ERROR: App Store Connect rejected the request (HTTP $HTTP) — check ASC credentials/permissions. Upload intact." >&2
  cat "$TMP_RESP" >&2
  exit 1
fi

# --- unhappy path: only a processing-state rejection is worth the VALID wait.
# Branch on the parsed error code/detail, NOT a grep over the whole body — auth
# messages contain "valid"/"invalid" and false-matched the old heuristic.
ERR_DETAIL="$(json_get '
import sys, json
d = json.load(sys.stdin)
errs = d.get("errors") or []
print(((errs[0].get("code") or "") + " " + (errs[0].get("detail") or "")) if errs else "")' < "$TMP_RESP")"

if printf '%s' "$ERR_DETAIL" | grep -qiE 'processing state|not in a valid|still processing|state.*not.*valid'; then
  echo "==> Write rejected (HTTP $HTTP) — build not yet VALID. Waiting (up to ~30 min)..."
  REACHED_VALID=0
  STATE=""
  for _ in $(seq 1 60); do
    STATE="$(asc_get "$API/builds/$BUILD_ID" 2>/dev/null | json_get '
import sys, json
print(json.load(sys.stdin).get("data", {}).get("attributes", {}).get("processingState", ""))')"
    if [ "$STATE" = "VALID" ]; then REACHED_VALID=1; break; fi
    if [ "$STATE" = "INVALID" ] || [ "$STATE" = "FAILED" ]; then
      echo "ERROR: build $BUILD_NUMBER processing state is $STATE (binary rejected by Apple). Upload intact; fix and re-deploy." >&2
      exit 1
    fi
    sleep 30
  done
  if [ "$REACHED_VALID" != "1" ]; then
    echo "ERROR: build $BUILD_NUMBER did not reach VALID within the wait (last state: ${STATE:-unknown}). Upload intact; re-run this script once processing completes." >&2
    exit 1
  fi
  LOC_ID="$(resolve_loc_id)"   # re-resolve: the first attempt may have created it
  HTTP="$(write_notes)"
  if [ "$HTTP" = "200" ] || [ "$HTTP" = "201" ]; then
    echo "==> Done (after wait). TestFlight 'What to Test' set for build $BUILD_NUMBER."
    exit 0
  fi
fi

echo "ERROR: setting 'What to Test' failed (HTTP $HTTP). Upload is intact; re-run this script:" >&2
cat "$TMP_RESP" >&2
exit 1
