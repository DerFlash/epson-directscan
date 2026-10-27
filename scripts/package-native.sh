#!/bin/bash
set -euo pipefail
umask 077
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Epson DirectScan Beta.app"
OUTPUT=''
REQUIRE_NOTARIZED=false
fail() { printf '%s\n' "$*" >&2; exit 1; }
while (($#)); do
  case "$1" in
    --app) [[ $# -ge 2 ]] || fail 'Missing --app value.'; APP="$2"; shift 2 ;;
    --output) [[ $# -ge 2 ]] || fail 'Missing --output value.'; OUTPUT="$2"; shift 2 ;;
    --require-notarized) REQUIRE_NOTARIZED=true; shift ;;
    *) fail 'Usage: package-native.sh [--app ABSOLUTE_APP] [--output ABSOLUTE_NEW_DIRECTORY] [--require-notarized]' ;;
  esac
done
[[ $(uname -s) == Darwin ]] || fail 'Packaging requires macOS.'
[[ "$APP" == /* && -d "$APP" && ! -L "$APP" ]] || fail 'Expected a real absolute app bundle path.'
PLIST="$APP/Contents/Info.plist"
[[ -f "$PLIST" && ! -L "$PLIST" ]] || fail 'Missing bundle Info.plist.'
read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }
[[ $(read_key CFBundleIdentifier) == org.scansmart.directscan.beta ]] || fail 'Unexpected app bundle identifier.'
[[ $(read_key CFBundleExecutable) == EpsonDirectScan ]] || fail 'Unexpected bundle executable.'
VERSION="$(read_key DirectScanVersion)"
BUILD="$(read_key CFBundleVersion)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$ ]] || fail 'Expected a release beta version.'
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || fail 'Invalid bundle build number.'
for EXE in "$APP/Contents/MacOS/EpsonDirectScan" "$APP/Contents/Helpers/EpsonButtonReceiver" "$APP/Contents/Helpers/EpsonFeedingWorker"; do
  [[ -f "$EXE" && ! -L "$EXE" && -x "$EXE" ]] || fail 'Missing regular executable in bundle.'
  codesign --verify --strict "$EXE" 2>/dev/null || fail 'Invalid executable signature.'
  [[ $(lipo -archs "$EXE") == arm64 ]] || fail 'This download package requires arm64 executables.'
done
codesign --verify --strict --deep "$APP" 2>/dev/null || fail 'Invalid app signature.'
for NOTICE in LICENSE.txt LICENSING.md; do
  BUNDLED_NOTICE="$APP/Contents/Resources/$NOTICE"
  SOURCE_NOTICE="$ROOT/$NOTICE"
  [[ "$NOTICE" != LICENSE.txt ]] || SOURCE_NOTICE="$ROOT/LICENSE"
  [[ -f "$BUNDLED_NOTICE" && ! -L "$BUNDLED_NOTICE" ]] || fail "Missing bundled licensing notice: $NOTICE. Rebuild the app."
  cmp -s "$SOURCE_NOTICE" "$BUNDLED_NOTICE" || fail "Stale bundled licensing notice: $NOTICE. Rebuild the app."
done
SIGNATURE="$(codesign -dv --verbose=4 "$APP" 2>&1)"
SIGNING='other'
if [[ "$SIGNATURE" == *'Signature=adhoc'* ]]; then SIGNING='ad-hoc'; fi
if [[ "$SIGNATURE" == *'Authority=Developer ID Application:'* ]]; then SIGNING='developer-id'; fi
NOTARIZED=false
if [[ "$SIGNING" == developer-id ]] && xcrun stapler validate "$APP" >/dev/null 2>&1; then NOTARIZED=true; fi
if $REQUIRE_NOTARIZED && ! $NOTARIZED; then fail 'A Developer-ID-signed app with a verified stapled notarization ticket is required.'; fi
STEM="epson-directscan-$VERSION-macos-arm64"
[[ -n "$OUTPUT" ]] || OUTPUT="$ROOT/dist/$STEM"
[[ "$OUTPUT" == /* ]] || fail 'Output must be an absolute new directory.'
[[ ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || fail 'Output already exists; choose a new directory.'
python3 - "$APP" "$OUTPUT" <<'PY'
from pathlib import Path
import sys
app=Path(sys.argv[1]).resolve(); out=Path(sys.argv[2]).resolve()
if out==app or app in out.parents: raise SystemExit('Output cannot be inside the app bundle.')
for p in app.rglob('*'):
    if p.is_symlink(): raise SystemExit('App bundle contains an unexpected symbolic link.')
    if p.suffix=='.framework': raise SystemExit('Do not package vendor frameworks inside this app.')
    if p.is_file():
        data=p.read_bytes()
        if any(marker in data for marker in [b'/Users/',b'/private/var/folders/',b'/var/folders/']):
            raise SystemExit('Private build path found in app; remove private debugging metadata before distribution.')
PY
PARENT="$(dirname -- "$OUTPUT")"
mkdir -p "$PARENT"
TASK_STAGE="$(mktemp -d "$PARENT/.directscan-package.XXXXXX")"
trap 'rm -rf -- "$TASK_STAGE"' EXIT
PAYLOAD="$TASK_STAGE/publish"
DMG_ROOT="$TASK_STAGE/dmg-root"
mkdir "$PAYLOAD" "$DMG_ROOT"
chmod 755 "$DMG_ROOT"
ditto "$APP" "$DMG_ROOT/Epson DirectScan Beta.app"
# Public copies must be readable by other users; preserve the private source.
chmod -R a+rX "$DMG_ROOT/Epson DirectScan Beta.app"
codesign --verify --strict --deep "$DMG_ROOT/Epson DirectScan Beta.app"
ln -s /Applications "$DMG_ROOT/Applications"
cp "$ROOT/LICENSE" "$DMG_ROOT/LICENSE.txt"
cp "$ROOT/LICENSING.md" "$DMG_ROOT/LICENSING.md"
if $NOTARIZED; then
  STATUS='Developer-ID-signiert; Notarisierungsticket geprüft.'
else
  STATUS='Diese Beta ist nicht notarisiert. macOS kann das erste Öffnen blockieren.'
fi
cat > "$DMG_ROOT/Installation.txt" <<EOF
Epson DirectScan $VERSION — Apple Silicon (arm64)

$STATUS

1. Epson ScanSmart, ältere AutoSave-Helfer und laufende DirectScan-Kopien beenden.
2. Neue Installation: Epson DirectScan Beta.app auf Applications ziehen.
   Update: die vorhandene App am selben Ort ersetzen, auch wenn sie unter
   Benutzer/Programme liegt. Keine zweite Kopie parallel betreiben. Den bisherigen
   Download bei Bedarf sichern; diese DMG führt keine Installationsskripte aus.
3. Den Epson-Treiber 6.7.84 separat installieren. ES-C320W per USB verbinden.
4. Die kopierte App starten, Ablageordner wählen und auf Bereit warten.

Falls macOS das erste Öffnen blockiert und du dieser Quelle vertraust:
Einmal das Öffnen versuchen, dann Systemeinstellungen > Datenschutz & Sicherheit
> Dennoch öffnen und die Nachfrage persönlich bestätigen. Die App und diese DMG
ändern keine Sicherheitseinstellungen. Keine Zugangsdaten weitergeben.

English: Quit old scan helpers. Drag the app to Applications, or replace an
existing copy at its original path. Install Epson driver 6.7.84 separately.
This beta may need your first-open confirmation in System Settings > Privacy &
Security. No developer tools or source compilation are needed to run this app.

Bestehende Einstellungen und Scans liegen außerhalb der App und bleiben beim
Ersetzen erhalten. Eine vorhandene Anmeldezuordnung benötigt denselben App-Pfad.
Die DMG installiert keinen Epson-Treiber und richtet keinen Autostart ein.

Anleitung und bekannte Beta-Grenzen:
https://github.com/DerFlash/epson-directscan/blob/main/docs/NATIVE.de.md

Lizenz: PolyForm Noncommercial 1.0.0. Kommerzielle Nutzung außerhalb der
ausdrücklichen Lizenzfreigaben benötigt vorherige schriftliche Genehmigung
von Björn Teichmann. Derzeit kein kommerzielles Verkaufsangebot.
License: PolyForm Noncommercial 1.0.0. Commercial use outside its express
permissions requires prior written permission. No commercial license is
currently offered for sale. See LICENSE.txt and LICENSING.md.
EOF
chmod 644 "$DMG_ROOT/Installation.txt" "$DMG_ROOT/LICENSE.txt" "$DMG_ROOT/LICENSING.md"
if ! hdiutil create -fs HFS+ -format UDZO -volname "Epson DirectScan $VERSION" -srcfolder "$DMG_ROOT" "$PAYLOAD/$STEM.dmg" > "$TASK_STAGE/image.log" 2>&1; then
  cat "$TASK_STAGE/image.log" >&2; fail 'Disk image creation failed.'
fi
hdiutil verify "$PAYLOAD/$STEM.dmg" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$DMG_ROOT/Epson DirectScan Beta.app" "$PAYLOAD/$STEM.zip"
python3 - "$VERSION" "$BUILD" "$SIGNING" "$NOTARIZED" "$PAYLOAD/PACKAGE-INFO.json" <<'PY'
from pathlib import Path
import json,sys
version,build,signing,notarized,output=sys.argv[1:]
Path(output).write_text(json.dumps(dict(version=version,build=build,architecture='arm64',signing=signing,notarized=notarized=='true',bundleID='org.scansmart.directscan.beta'),indent=2)+'\n')
PY
(cd "$PAYLOAD" && shasum -a 256 "$STEM.dmg" "$STEM.zip" > SHA256SUMS)
# Darwin's exclusive directory rename prevents a concurrent output from being replaced.
python3 - "$PAYLOAD" "$OUTPUT" <<'PY'
import ctypes,errno,os,sys
lib=ctypes.CDLL('/usr/lib/libSystem.B.dylib',use_errno=True)
rename=lib.renamex_np; rename.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_uint]; rename.restype=ctypes.c_int
# stdio.h: RENAME_EXCL = 0x00000004.
if rename(os.fsencode(sys.argv[1]),os.fsencode(sys.argv[2]),4):
    code=ctypes.get_errno()
    if code==errno.EEXIST: raise SystemExit('Output already exists; no package replaced.')
    raise OSError(code,os.strerror(code))
PY
printf 'Packaged %s (signing: %s, notarized: %s)\n' "$OUTPUT" "$SIGNING" "$NOTARIZED"
