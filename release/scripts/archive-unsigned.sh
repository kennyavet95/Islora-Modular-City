#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ARCHIVE_PATH="${1:-$REPO_ROOT/build_out/Islora-final-unsigned.xcarchive}"
cd "$REPO_ROOT"
python3 release/scripts/validate.py
xcodebuild archive \
  -project Blockora.xcodeproj \
  -scheme Islora \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$REPO_ROOT/build_out/IsloraReleaseDerivedData" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
python3 release/scripts/validate.py "$ARCHIVE_PATH"
echo "Unsigned validation archive created. A signed App Store IPA requires the new account."
