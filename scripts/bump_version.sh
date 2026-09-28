#!/bin/bash
# Bump LastNote's version for a new update and print the new version.
#   0.1.0 -> 0.1.1 -> … -> 0.1.99 -> 0.2.0   (patch rolls over into the next minor at 100)
# The build number (CFBundleVersion) always goes up by one.
set -euo pipefail
cd "$(dirname "$0")/.."
PLIST=Resources/Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
IFS=. read -r MAJOR MINOR PATCH <<<"$VERSION"
PATCH=$((PATCH + 1))
if [ "$PATCH" -ge 100 ]; then
  MINOR=$((MINOR + 1))
  PATCH=0
fi
NEW="$MAJOR.$MINOR.$PATCH"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "$PLIST"
echo "$NEW"
