#!/bin/bash
# Build LastNote and install it to /Applications (quits the running copy first).
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/bundle.sh
osascript -e 'quit app "LastNote"' 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x LastNote >/dev/null || break; sleep 0.5; done
if pgrep -x LastNote >/dev/null; then echo "LastNote is still open (unsaved changes?). Quit it and run again."; exit 1; fi
rm -rf /Applications/LastNote.app
ditto build/LastNote.app /Applications/LastNote.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/LastNote.app
echo "Installed /Applications/LastNote.app"
open /Applications/LastNote.app
