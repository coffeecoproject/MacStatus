#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="${1:-MacStatus.dmg}"
if [[ $# -gt 1 || "$name" != *.dmg || "$name" == */* || "$name" == .* || "$name" == -* ]]; then
    printf 'Usage: bash Scripts/build-dmg.sh [DMG_FILENAME.dmg]\n' >&2
    exit 2
fi
output="$root/dist/$name"
python3 - "$output" <<'PY'
from pathlib import Path
import plistlib
import subprocess
import sys

output = Path(sys.argv[1]).resolve()
info = plistlib.loads(subprocess.run(
    ["/usr/bin/hdiutil", "info", "-plist"], capture_output=True, check=True
).stdout)
for image in info.get("images", []):
    path = image.get("image-path")
    if path and Path(path).resolve() == output:
        raise SystemExit("Output image is mounted; eject it manually or choose another DMG filename.")
PY

bash "$root/Scripts/build-app.sh" release
app="$root/.build/app/release/MacStatus.app"
bash "$root/Tests/Packaging/verify-bundle.sh" --strict-signature "$app"

work="$(mktemp -d "$root/.build/dmg.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir "$work/content"
/usr/bin/ditto "$app" "$work/content/MacStatus.app"
ln -s /Applications "$work/content/Applications"
/usr/bin/hdiutil create -volname MacStatus -fs HFS+ -format UDZO \
    -srcfolder "$work/content" "$work/MacStatus.dmg"
/usr/bin/hdiutil verify "$work/MacStatus.dmg"
mkdir -p "$root/dist"
mv -f "$work/MacStatus.dmg" "$output"
printf '\nBuilt local-use DMG: %s\n' "$output"
