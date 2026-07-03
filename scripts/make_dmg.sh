#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Carlos B and kefbar contributors
#
# This file is part of kefbar.
#
# Build a drag-to-Applications DMG for kefbar (SPEC §13). Uses only hdiutil —
# no Homebrew / create-dmg dependency, in keeping with the project's native,
# least-code ethos. Signing + notarisation are deferred (SPEC §13): the app
# inside is signed with whatever identity `make app` used.
#
# Usage: scripts/make_dmg.sh [path/to/kefbar.app]
set -euo pipefail

APP="${1:-build/kefbar.app}"
VOLNAME="kefbar"
OUT="build/kefbar.dmg"

if [ ! -d "$APP" ]; then
  echo "error: '$APP' not found — run 'make app' first." >&2
  exit 1
fi

# Name the image with the app version when available (e.g. build/kefbar-1.0.dmg).
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$APP/Contents/Info.plist" 2>/dev/null || true)"
[ -n "${VERSION:-}" ] && OUT="build/kefbar-${VERSION}.dmg"

STAGE="$(mktemp -d)"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

# Stage the app beside a symlink to /Applications so the user just drags across.
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# A styled background image + arranged icon positions would go here (Finder
# scripting on a read-write image, then convert to UDZO). That needs brand
# assets — an .icns and a background .png — which don't exist yet, so we ship
# the clean functional layout for now. Wire it up when the artwork lands.

mkdir -p build
rm -f "$OUT"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 \
  -ov "$OUT" >/dev/null

# Sanity-check the result is a mountable image.
hdiutil imageinfo "$OUT" >/dev/null

echo "built $OUT ($(du -h "$OUT" | cut -f1))"
