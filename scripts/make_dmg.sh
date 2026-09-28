#!/bin/bash
# Build a universal (Apple Silicon + Intel) LastNote.app and package it as a shareable .dmg.
# Output: build/LastNote-<version>.dmg
#
# Signing: with a Developer ID identity set in LASTNOTE_SIGN_ID (e.g. "Developer ID Application:
# Your Name (TEAMID)") the app is signed for distribution and can then be notarized. Without it the
# app is ad-hoc signed, which runs on other Macs only after the user approves it (see the
# "How to open" note inside the .dmg).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
APP=build/dmg-staging/LastNote.app
DMG=build/LastNote-$VERSION.dmg

echo "Building arm64…";  swift build -c release --triple arm64-apple-macosx13.0  >/dev/null
echo "Building x86_64…"; swift build -c release --triple x86_64-apple-macosx13.0 >/dev/null
ARM=$(swift build -c release --triple arm64-apple-macosx13.0 --show-bin-path)/LastNote
X86=$(swift build -c release --triple x86_64-apple-macosx13.0 --show-bin-path)/LastNote

rm -rf build/dmg-staging "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM" "$X86" -output "$APP/Contents/MacOS/LastNote"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if [ -n "${LASTNOTE_SIGN_ID:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$LASTNOTE_SIGN_ID" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

ln -s /Applications build/dmg-staging/Applications
cat > "build/dmg-staging/How to open LastNote.txt" <<'TXT'
Installing LastNote
===================

1. Drag LastNote onto the Applications folder in this window.
2. Open LastNote from Applications.

The first time, macOS may say LastNote "cannot be opened" or "could not verify" it,
because it isn't distributed through the App Store or signed with an Apple Developer ID.
To allow it (only needed once):

  - Open System Settings > Privacy & Security.
  - Scroll down to the message about LastNote and click "Open Anyway".
  - Confirm with your password or Touch ID.

LastNote runs on macOS 13 (Ventura) or later, on Apple Silicon and Intel Macs.
TXT

hdiutil create -volname "LastNote $VERSION" -srcfolder build/dmg-staging -ov -format UDZO "$DMG" >/dev/null
rm -rf build/dmg-staging
echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
