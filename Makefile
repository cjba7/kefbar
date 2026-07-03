# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Carlos B and kefbar contributors
#
# This file is part of kefbar.

PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
RELEASE_BIN := .build/release/kefbar

.PHONY: all build release debug test clean mock mock-legacy run sign install uninstall app dmg

# Code-signing identity used by `make sign`. A fresh `swift build` links ad-hoc,
# which cannot hold a macOS 15+ Local Network grant; re-sign with a stable identity.
# Override for release: make sign SIGN_IDENTITY="Developer ID Application: …"
SIGN_IDENTITY ?= kefbar-codesign

all: release

## build (alias for release)
build: release

## release: optimised CLI + KEFKit
release:
	swift build -c release

## sign the release CLI with $(SIGN_IDENTITY) so it can hold a Local Network grant
sign: release
	codesign --force --sign "$(SIGN_IDENTITY)" .build/release/kefbar
	@codesign -dvvv .build/release/kefbar 2>&1 | grep -iE "Identifier=|Authority=" || true

## debug build
debug:
	swift build

## run unit tests
test:
	swift test

## run the mock KEF speaker (127.0.0.1:8080) for local testing
mock:
	python3 scripts/mock_kef.py 8080

## run the mock in legacy GET-only mode (simulates old firmware)
mock-legacy:
	KEF_MOCK_GETONLY=1 python3 scripts/mock_kef.py 8080

## run the debug CLI, e.g.  make run ARGS="--host 192.168.1.114 get"
run:
	swift run kefbar $(ARGS)

## install the release CLI into $(BINDIR) (may require sudo depending on PREFIX)
install: release
	install -d "$(BINDIR)"
	install -m 0755 "$(RELEASE_BIN)" "$(BINDIR)/kefbar"
	@echo "installed $(BINDIR)/kefbar"

## remove the installed CLI
uninstall:
	rm -f "$(BINDIR)/kefbar"

## menu-bar app bundle (M3): build the SwiftUI executable and wrap it into kefbar.app
APP_BUNDLE := build/kefbar.app
app:
	swift build -c release --product KefbarApp
	swift build -c release --product kefbar
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources" "$(APP_BUNDLE)/Contents/Helpers"
	cp .build/release/KefbarApp "$(APP_BUNDLE)/Contents/MacOS/KefbarApp"
	cp .build/release/kefbar "$(APP_BUNDLE)/Contents/Helpers/kefbar"
	cp App/Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --sign "$(SIGN_IDENTITY)" "$(APP_BUNDLE)/Contents/Helpers/kefbar"
	codesign --force --sign "$(SIGN_IDENTITY)" "$(APP_BUNDLE)"
	@echo "built $(APP_BUNDLE) — launch with: open $(APP_BUNDLE)"

## drag-to-Applications DMG — milestone M4
dmg: app
	bash scripts/make_dmg.sh "$(APP_BUNDLE)"

## remove build products
clean:
	swift package clean
	rm -rf .build
