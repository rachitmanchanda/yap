#!/bin/sh

set -eu

SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIRECTORY=$(CDPATH= cd -- "$SCRIPT_DIRECTORY/../.." && pwd)
DESTINATION=${1:-"platform=iOS Simulator,name=iPhone 17 Pro"}

cd "$PROJECT_DIRECTORY"

python3 Tools/UIAudit/ui_audit.py --strict

xcodebuild \
  -project Yap.xcodeproj \
  -scheme VoiceCards \
  -configuration Debug \
  -destination "$DESTINATION" \
  build

xcodebuild \
  -project Yap.xcodeproj \
  -scheme VoiceCards \
  -destination "$DESTINATION" \
  -only-testing:YapUITests/VoiceCardsUITests/testDesignSystemGallerySupportsLargeText \
  test
