#!/bin/bash
set -e

# Archive and upload DOSBTS to TestFlight via App Store Connect API
# Usage: ./deploy.sh

ARCHIVE_PATH="build/DOSBTS.xcarchive"
EXPORT_PATH="build/export"

# ASC credentials. The archive/upload below authenticate with these; they are
# also exported so scripts/asc-release-notes.sh (which carries no literals) can
# reuse them. Override any via the environment. ASC_APP_ID (numeric App Store
# Connect app id) has no default — set it in your environment to enable the
# release-notes push.
export ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.private_keys/AuthKey_2CY3778TFY.p8}"
export ASC_KEY_ID="${ASC_KEY_ID:-2CY3778TFY}"
export ASC_ISSUER_ID="${ASC_ISSUER_ID:-69a6de7d-b4e1-47e3-e053-5b8c7c11a4d1}"

# --- Pre-flight: refuse to archive a build number already on TestFlight -------
# ASC auto-manages build numbers, so re-uploading an already-shipped
# CURRENT_PROJECT_VERSION gets silently renumbered and desyncs git/CHANGELOG from
# TestFlight (the Build 109/110 drift). Best-effort: needs ASC_APP_ID; a query
# failure warns and proceeds, a confirmed collision aborts before archiving.
API_V1="https://api.appstoreconnect.apple.com/v1"
LOCAL_BUILD="$(grep -m1 'CURRENT_PROJECT_VERSION = ' DOSBTS.xcodeproj/project.pbxproj | tr -dc '0-9')"
if [ -n "${ASC_APP_ID:-}" ] && [ -n "$LOCAL_BUILD" ]; then
  echo "==> Pre-flight: confirming build $LOCAL_BUILD isn't already on TestFlight..."
  _JWT="$(python3 scripts/asc-jwt.py "$ASC_KEY_PATH" "$ASC_KEY_ID" "$ASC_ISSUER_ID" 300 2>/dev/null || true)"
  ASC_MAX=""
  if [ -n "$_JWT" ]; then
    ASC_MAX="$(curl -fsS -H "Authorization: Bearer $_JWT" \
      "$API_V1/builds?filter%5Bapp%5D=$ASC_APP_ID&sort=-uploadedDate&limit=1" 2>/dev/null \
      | python3 -c 'import sys, json
try:
    d = json.load(sys.stdin); data = d.get("data") or []
    print(data[0].get("attributes", {}).get("version") if data else "")
except Exception:
    print("")' 2>/dev/null || true)"
  fi
  unset _JWT
  if ! printf '%s' "$ASC_MAX" | grep -qE '^[0-9]+$'; then
    echo "    WARN: could not read the latest TestFlight build (creds/network?); proceeding without the guard." >&2
  elif [ "$LOCAL_BUILD" -le "$ASC_MAX" ]; then
    echo "ERROR: build $LOCAL_BUILD is already on TestFlight (latest there is $ASC_MAX)." >&2
    echo "       Bump CURRENT_PROJECT_VERSION to $((ASC_MAX + 1)) in all 4 places and promote the CHANGELOG, then re-run." >&2
    exit 1
  else
    echo "    OK — $LOCAL_BUILD is ahead of TestFlight's latest ($ASC_MAX)."
  fi
else
  [ -z "${ASC_APP_ID:-}" ] && echo "==> Pre-flight build-collision check skipped (set ASC_APP_ID to enable)."
fi

echo "==> Cleaning build directory..."
rm -rf build/

# Refresh the in-app changelog copy BEFORE archiving — the archive snapshots
# the bundle, so refreshing afterward would ship the previous deploy's
# changelog. This is what makes the in-app "What's New" reflect the build it
# ships in (DMNC-1147). (Promote [Unreleased] → [Build N] before running this.)
echo "==> Refreshing bundled changelog (Library/Resources/CHANGELOG.md)..."
cp CHANGELOG.md Library/Resources/CHANGELOG.md

echo "==> Archiving..."
xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSApp \
  -destination 'generic/platform=iOS' -configuration Release \
  archive -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -quiet

echo "==> Uploading to TestFlight..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

# Derive the build's TestFlight "What to Test" from the latest [Build N] block
# and push it (DMNC-1147). Wrapped so a notes failure can never abort the
# deploy — the upload above already succeeded. Skipped (with a hint) when
# ASC_APP_ID is unset. Re-runnable on its own: ./scripts/asc-release-notes.sh
if [ -n "${ASC_APP_ID:-}" ]; then
  echo "==> Setting TestFlight release notes from CHANGELOG..."
  ( ./scripts/asc-release-notes.sh ) \
    || echo "WARN: notes push failed; upload intact — re-run ./scripts/asc-release-notes.sh"
else
  echo "==> Skipping release notes (set ASC_APP_ID to enable). Upload is complete."
fi

echo "==> Done! Build uploaded to TestFlight."
