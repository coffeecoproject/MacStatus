#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app="$root/.build/app/debug/MacStatus.app"
strict_signature=false
app_supplied=false

usage() {
    printf 'Usage: bash Tests/Packaging/verify-bundle.sh [--strict-signature] [APP_PATH]\n'
}

for argument in "$@"; do
    case "$argument" in
        --strict-signature) strict_signature=true ;;
        --help|-h) usage; exit 0 ;;
        -*) usage >&2; exit 2 ;;
        *)
            if [ "$app_supplied" = true ]; then usage >&2; exit 2; fi
            app="$argument"
            app_supplied=true
            ;;
    esac
done

plist="$app/Contents/Info.plist"
/usr/bin/plutil -lint "$plist"
executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
package_type="$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$plist")"
agent_app="$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$plist")"
if [ "$executable_name" != MacStatus ] || [ "$package_type" != APPL ] || [ "$agent_app" != true ]; then
    printf 'Unexpected MacStatus application metadata\n' >&2
    exit 1
fi

executable="$app/Contents/MacOS/$executable_name"
if [ ! -x "$executable" ]; then
    printf 'Missing or non-executable app binary: %s\n' "$executable" >&2
    exit 1
fi
/usr/bin/lipo "$executable" -verify_arch "$(/usr/bin/uname -m)"
printf 'PASS: local app metadata, executable and host architecture\n'

if [ "$strict_signature" = true ]; then
    /usr/bin/codesign --verify --strict --verbose=2 "$app"
    printf 'PASS: full app bundle signature\n'
else
    printf 'SKIP: full bundle signature is optional for local use (--strict-signature to check)\n'
fi
