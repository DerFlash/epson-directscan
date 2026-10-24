#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/ScanSmart AutoSave Beta.app"
IDENTITY='-'
REPLACE=false
while (($#)); do
  case "$1" in
    --replace) REPLACE=true; shift ;;
    --sign) [[ $# -ge 2 && -n "$2" ]] || { echo 'Missing signing identity.' >&2; exit 2; }; IDENTITY="$2"; shift 2 ;;
    *) echo "Usage: $0 [--replace] [--sign IDENTITY]" >&2; exit 2 ;;
  esac
done
[[ $(uname -s) == Darwin ]] || { echo 'Build requires macOS.' >&2; exit 1; }
for file in src/helper.applescript src/core.js src/runtime.js src/native-click.js; do
  [[ -f "$ROOT/$file" ]] || { echo "Missing source: $file" >&2; exit 1; }
done
if [[ -e "$APP" || -L "$APP" ]]; then
  $REPLACE || { echo 'Build exists; use --replace to replace this build output.' >&2; exit 1; }
fi
mkdir -p "$ROOT/build"
TEMP="$(mktemp -d "$ROOT/build/.build.XXXXXX")"
trap 'rm -rf -- "$TEMP"' EXIT
/usr/bin/osacompile -s -o "$TEMP/ScanSmart AutoSave Beta.app" "$ROOT/src/helper.applescript"
BUNDLE="$TEMP/ScanSmart AutoSave Beta.app"
mkdir -p "$BUNDLE/Contents/Resources"
for file in core.js runtime.js native-click.js; do
  /bin/cp "$ROOT/src/$file" "$BUNDLE/Contents/Resources/$file"
done
PLIST="$BUNDLE/Contents/Info.plist"
set_key() {
  /usr/libexec/PlistBuddy -c "Delete :$1" "$PLIST" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PLIST"
}
set_key CFBundleIdentifier org.scansmart.autosave.beta
set_key CFBundleDisplayName 'ScanSmart AutoSave Beta'
set_key CFBundleName 'ScanSmart AutoSave Beta'
set_key CFBundleShortVersionString 0.1.0
set_key CFBundleVersion 1
set_key AutoSaveVersion 0.1.0-beta.1
set_key NSAppleEventsUsageDescription 'Read the German Epson ScanSmart save window through System Events and complete explicitly enabled JPG exports.'
/usr/bin/plutil -lint "$PLIST"
/usr/bin/codesign --force --sign "$IDENTITY" "$BUNDLE"
/usr/bin/codesign --verify --strict "$BUNDLE"
if [[ -e "$APP" || -L "$APP" ]]; then rm -rf -- "$APP"; fi
/bin/mv "$BUNDLE" "$APP"
printf 'Built %s\n' "$APP"
