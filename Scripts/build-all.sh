#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Twarge LLC
# SPDX-License-Identifier: Apache-2.0
#
# Builds every scheme exactly as Xcode's Build does: the same project, the default
# DerivedData location, and normal signing — so the products are byte-for-byte what ⌘B
# produces, and the registered app/widgets on this machine are always the ones just built.
#
# Pass simulator name overrides with IOS_SIM / WATCH_SIM if the defaults aren't installed.

set -euo pipefail

cd "$(dirname "$0")/.."

IOS_SIM="${IOS_SIM:-iPhone 17 Pro}"
WATCH_SIM="${WATCH_SIM:-Apple Watch Series 11 (46mm)}"

echo "==> Building Observatory (macOS)"
xcodebuild -project Geomagnetic.xcodeproj -scheme Observatory \
  -destination 'platform=macOS,arch=arm64' build

echo "==> Building Observatory (iOS Simulator: $IOS_SIM)"
xcodebuild -project Geomagnetic.xcodeproj -scheme Observatory \
  -destination "platform=iOS Simulator,name=$IOS_SIM" build

echo "==> Building Observatory Watch (watchOS Simulator: $WATCH_SIM)"
xcodebuild -project Geomagnetic.xcodeproj -scheme ObservatoryWatch \
  -destination "platform=watchOS Simulator,name=$WATCH_SIM" build

echo "All builds succeeded."
