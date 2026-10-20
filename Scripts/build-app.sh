#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${1:-debug}"
case "$configuration" in
    debug|release) ;;
    *) printf 'Usage: bash Scripts/build-app.sh [debug|release]\n' >&2; exit 1 ;;
esac

swift build --package-path "$root" --configuration "$configuration" --product MacStatus
bin_dir="$(swift build --package-path "$root" --configuration "$configuration" --show-bin-path)"
app="$root/.build/app/$configuration/MacStatus.app"

mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/MacStatus" "$app/Contents/MacOS/MacStatus"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign - --timestamp=none "$app"
printf '\nBuilt: %s\n' "$app"
