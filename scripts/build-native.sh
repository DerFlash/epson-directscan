#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Epson DirectScan Beta.app"
REPLACE=false
if [[ ${1:-} == --replace ]]; then REPLACE=true; shift; fi
[[ $# == 0 ]] || { echo 'Usage: build-native.sh [--replace]' >&2; exit 2; }
if [[ -e "$APP" || -L "$APP" ]]; then
  $REPLACE || { echo 'Native build exists; use --replace.' >&2; exit 1; }
fi
swift build --package-path "$ROOT/native" -c release --product EpsonDirectScan
BIN="$(swift build --package-path "$ROOT/native" -c release --show-bin-path)"
mkdir -p "$ROOT/build"
TASK_BUILD="$(mktemp -d "$ROOT/build/.native-build.XXXXXX")"
trap 'rm -rf -- "$TASK_BUILD"' EXIT
BUNDLE="$TASK_BUILD/Epson DirectScan Beta.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Helpers"
cp "$BIN/EpsonDirectScan" "$BUNDLE/Contents/MacOS/"
clang -fobjc-arc -mmacosx-version-min=13.0 -framework AppKit -framework IOKit \
  "$ROOT/native/Helpers/EpsonButtonReceiver.m" -o "$BUNDLE/Contents/Helpers/EpsonButtonReceiver"
codesign --force --sign - "$BUNDLE/Contents/Helpers/EpsonButtonReceiver"
cp "$ROOT/native/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
plutil -lint "$BUNDLE/Contents/Info.plist"
codesign --force --sign - "$BUNDLE"
codesign --verify --strict "$BUNDLE"
if [[ -e "$APP" || -L "$APP" ]]; then rm -rf -- "$APP"; fi
mv "$BUNDLE" "$APP"
printf 'Built %s\n' "$APP"
