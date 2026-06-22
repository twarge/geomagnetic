#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Twarge LLC
# SPDX-License-Identifier: Apache-2.0
#
# Regenerates the Xcode project and builds every target for every platform. Pass a
# simulator name override with IOS_SIM / WATCH_SIM if the defaults aren't installed.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="observatory.xcodeproj"
DERIVED="build/DerivedData"
IOS_SIM="${IOS_SIM:-iPhone 17 Pro}"
WATCH_SIM="${WATCH_SIM:-Apple Watch Series 11 (46mm)}"
COMMON=(-project "$PROJECT" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO)

echo "==> Regenerating $PROJECT"
python3 Scripts/generate-project.py

echo "==> Building Observatory (macOS)"
xcodebuild "${COMMON[@]}" -scheme Observatory -destination 'platform=macOS,arch=arm64' build

echo "==> Building Observatory (iOS Simulator: $IOS_SIM)"
xcodebuild "${COMMON[@]}" -scheme Observatory -destination "platform=iOS Simulator,name=$IOS_SIM" build

echo "==> Building Observatory Watch (watchOS Simulator: $WATCH_SIM)"
xcodebuild "${COMMON[@]}" -scheme ObservatoryWatch -destination "platform=watchOS Simulator,name=$WATCH_SIM" build

echo "All builds succeeded."
