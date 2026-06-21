#!/bin/bash
#
# check-changelog-parity.sh — guards the KTD2 metadata-strip grammar (DMNC-1147).
#
# The cleaner exists twice: perl (strip-changelog-metadata.pl, used by
# asc-release-notes.sh for TestFlight notes) and Swift (ChangelogParser, used by
# the in-app What's New). They must strip identically or the two surfaces diverge.
# This script pins the perl side to explicit expected outputs; ChangelogParserTests
# pins the Swift side to the SAME expectations (stripsTrailingMetadata et al.).
# A drift in either implementation fails its own check.
#
# Run manually, in CI, or from a pre-commit hook:  scripts/check-changelog-parity.sh
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
STRIP="$DIR/strip-changelog-metadata.pl"
fail=0

check() {  # <input-line> <expected-output>
  local got
  got="$(printf '%s\n' "$1" | perl "$STRIP")"
  if [ "$got" != "$2" ]; then
    printf 'PARITY FAIL\n  in:  %s\n  got: %s\n  exp: %s\n' "$1" "$got" "$2" >&2
    fail=1
  fi
}

# These mirror ChangelogParserTests (stripsTrailingMetadata / stripsChainedMetadata
# / preservesProseEmDash / keepsNonMetadataTail / extractsTourMarker). The leading
# "- " stays here (the bullet→• step is presentation, applied after the strip).
check "- Pulsing dots loading indicator — DMNC-797"                                   "- Pulsing dots loading indicator"
check "- Correction bolus cue — DMNC-715, PR #62"                                     "- Correction bolus cue"
check "- Infographic digest — PR #54."                                               "- Infographic digest"
check "- Y-axis flush with edge — DMNC-1045 follow-up"                               "- Y-axis flush with edge"
check "- Siri logging — DMNC-633, DMNC-634."                                          "- Siri logging"
check "- Shared meal row component (deleting required edit mode) — R3, R4, AE4 — PR #52." "- Shared meal row component (deleting required edit mode)"
check "- A toast lights up — the app's first positive feedback — DMNC-772, PR #59."  "- A toast lights up — the app's first positive feedback"
check "- Predictive low alarm — 20-min forward extrapolation of trajectory"          "- Predictive low alarm — 20-min forward extrapolation of trajectory"
check "- Day/night alarm profiles {tour:settings/alarms} — DMNC-692"                 "- Day/night alarm profiles"

if [ "$fail" = 0 ]; then
  echo "changelog parity: OK"
else
  echo "changelog parity: DRIFT DETECTED — perl strip disagrees with the pinned expectations" >&2
  exit 1
fi
