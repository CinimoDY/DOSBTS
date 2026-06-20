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
# Optional: EDITOR (default vi), CHANGELOG (default CHANGELOG.md).
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

# --- 2. clean → TestFlight notes (same KTD2 grammar as ChangelogParser) -----
# Strips the {tour:} marker and trailing developer metadata (iteratively, so
# chained '— A — B' runs are removed), uppercases group headers, and bullets
# entries. \x{2014} is the em dash; a trailing segment that does not start with
# a known issue token (a prose em-dash) is left intact.
# [ \t]* (not \s*) at the tail so the iterative strip never eats the line's
# own newline and collapses adjacent bullets together.
NOTES_BODY="$(printf '%s\n' "$BLOCK" | perl -CSD -pe '
  s/[ \t]*\{tour:[^}]*\}//g;
  1 while s/[ \t]+\x{2014}[ \t]+(?:DMNC-\d+|PR\ \#\d+|R\d+|AE\d+|D\d+|[A-Z]{2,}-\d+)(?:,?[ \t]+(?:DMNC-\d+|PR\ \#\d+|R\d+|AE\d+|D\d+|[A-Z]{2,}-\d+|[a-z][a-z-]+|\([^)]*\)))*\.?[ \t]*$//;
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

# whatsToTest has a 4000-CHARACTER ASC limit; warn but proceed (the API would
# 409). Count characters with perl, not `wc -c` (bytes) — the cleaned text is
# em-dash / bullet heavy (3 bytes each in UTF-8), so a byte count overcounts.
NOTE_LEN="$(perl -CSD -e 'local $/; my $s = <STDIN>; print length($s // "")' < "$TMP_NOTES")"
if [ "${NOTE_LEN:-0}" -gt 4000 ]; then
  echo "WARNING: notes are ${NOTE_LEN} chars; ASC caps whatsToTest at 4000. Trim in the editor." >&2
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

# --- 4. poll until the build registers in ASC (KTD8) -----------------------
echo "==> Waiting for build $BUILD_NUMBER to register in App Store Connect (up to ~15 min)..."
BUILD_QUERY="filter%5Bapp%5D=$ASC_APP_ID&filter%5Bversion%5D=$BUILD_NUMBER&filter%5Bplatform%5D=IOS&sort=-uploadedDate&limit=1"
BUILD_ID=""
for _ in $(seq 1 30); do
  RESP="$(asc_get "$API/builds?$BUILD_QUERY" 2>/dev/null || true)"
  BUILD_ID="$(printf '%s' "$RESP" | json_get '
import sys, json
d = json.load(sys.stdin)
print(d["data"][0]["id"] if d.get("data") else "")')"
  [ -n "$BUILD_ID" ] && break
  sleep 30
done

if [ -z "$BUILD_ID" ]; then
  echo "ERROR: build $BUILD_NUMBER did not register within the timeout. Re-run later." >&2
  exit 1
fi
echo "==> Found build $BUILD_NUMBER (id $BUILD_ID)."

# --- 5. find an existing en-US localization, then PATCH or POST ------------
LOC_RESP="$(asc_get "$API/builds/$BUILD_ID/betaBuildLocalizations" 2>/dev/null || true)"
LOC_ID="$(printf '%s' "$LOC_RESP" | json_get '
import sys, json
d = json.load(sys.stdin)
print(next((x["id"] for x in d.get("data", []) if x.get("attributes", {}).get("locale") == "en-US"), ""))')"

write_notes() {
  # Build the JSON body in python (whatsToTest passed via env, never via the
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
      "attributes": {"whatsToTest": notes}}}))' \
    | curl -sS -X PATCH \
        -H "Authorization: Bearer $jwt" -H "Content-Type: application/json" \
        --data-binary @- -o "$TMP_RESP" -w '%{http_code}' \
        "$API/betaBuildLocalizations/$LOC_ID"
  else
    NOTES_FILE="$TMP_NOTES" BUILD_ID="$BUILD_ID" python3 -c '
import json, os
notes = open(os.environ["NOTES_FILE"], encoding="utf-8").read()
print(json.dumps({"data": {"type": "betaBuildLocalizations",
      "attributes": {"locale": "en-US", "whatsToTest": notes},
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

# --- unhappy path: a write rejected because the build is still PROCESSING ---
if grep -qiE 'processing|not.*valid|state' "$TMP_RESP"; then
  echo "==> Write rejected ($HTTP) — build may still be processing. Waiting for VALID (up to ~30 min)..."
  for _ in $(seq 1 60); do
    STATE="$(asc_get "$API/builds/$BUILD_ID" 2>/dev/null | json_get '
import sys, json
print(json.load(sys.stdin).get("data", {}).get("attributes", {}).get("processingState", ""))')"
    [ "$STATE" = "VALID" ] && break
    sleep 30
  done
  HTTP="$(write_notes)"
  if [ "$HTTP" = "200" ] || [ "$HTTP" = "201" ]; then
    echo "==> Done (after wait). TestFlight 'What to Test' set for build $BUILD_NUMBER."
    exit 0
  fi
fi

echo "ERROR: setting 'What to Test' failed (HTTP $HTTP). Upload is intact; re-run this script:" >&2
cat "$TMP_RESP" >&2
exit 1
