#!/bin/bash
set -e

# Archive and upload DOSBTS to TestFlight via App Store Connect API
# Usage: ./deploy.sh

ARCHIVE_PATH="build/DOSBTS.xcarchive"
EXPORT_PATH="build/export"

echo "==> Cleaning build directory..."
rm -rf build/

echo "==> Archiving..."
xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSApp \
  -destination 'generic/platform=iOS' -configuration Release \
  archive -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.private_keys/AuthKey_2CY3778TFY.p8 \
  -authenticationKeyID 2CY3778TFY \
  -authenticationKeyIssuerID 69a6de7d-b4e1-47e3-e053-5b8c7c11a4d1 \
  -quiet

echo "==> Uploading to TestFlight..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.private_keys/AuthKey_2CY3778TFY.p8 \
  -authenticationKeyID 2CY3778TFY \
  -authenticationKeyIssuerID 69a6de7d-b4e1-47e3-e053-5b8c7c11a4d1

echo "==> Done! Build uploaded to TestFlight."
