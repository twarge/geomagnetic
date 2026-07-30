# SPDX-FileCopyrightText: 2026 Twarge LLC
# SPDX-License-Identifier: Apache-2.0
#
# Builds exactly as Xcode's Build does: the same project, the default DerivedData
# location, and normal signing — so the products are byte-for-byte what ⌘B produces.
# Override the simulators with IOS_SIM / WATCH_SIM if the defaults aren't installed.

IOS_SIM ?= iPhone 17 Pro
WATCH_SIM ?= Apple Watch Series 11 (46mm)
PROJECT := Geomagnetic.xcodeproj

.PHONY: all macos ios watchos help

all: macos ios watchos ## Build every platform

macos: ## Build the macOS app
	xcodebuild -project $(PROJECT) -scheme Observatory \
	  -destination 'platform=macOS,arch=arm64' build

ios: ## Build the iOS app for the simulator
	xcodebuild -project $(PROJECT) -scheme Observatory \
	  -destination 'platform=iOS Simulator,name=$(IOS_SIM)' build

watchos: ## Build the watch app for the simulator
	xcodebuild -project $(PROJECT) -scheme ObservatoryWatch \
	  -destination 'platform=watchOS Simulator,name=$(WATCH_SIM)' build

help: ## List targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'
