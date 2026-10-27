#!/bin/bash
set -euo pipefail
umask 077
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/build/Epson DirectScan Beta.app"
DEST="$HOME/Applications/Epson DirectScan Beta.app"
REPLACE=false
if [[ ${1:-} == --replace ]]; then REPLACE=true; shift; fi
[[ $# == 0 ]] || { echo 'Usage: install-native.sh [--replace]' >&2; exit 2; }
[[ -d "$SOURCE" ]] || { echo 'Build the native app first.' >&2; exit 1; }
if [[ -e "$DEST" || -L "$DEST" ]]; then
  $REPLACE || { echo 'Native app exists; quit it and use --replace.' >&2; exit 1; }
  [[ -d "$DEST" && ! -L "$DEST" ]] || { echo 'Unexpected native app target.' >&2; exit 1; }
  TASK_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist")"
  [[ "$TASK_ID" == org.scansmart.directscan.beta ]] || { echo 'Target is a different app.' >&2; exit 1; }
fi
while IFS= read -r TASK_COMMAND; do
  case "$TASK_COMMAND" in
    *'/Epson DirectScan Beta.app/Contents/MacOS/EpsonDirectScan') echo 'Quit the native app first.' >&2; exit 1 ;;
  esac
done < <(/bin/ps -ax -o comm=)
codesign --verify --strict "$SOURCE"
mkdir -p "$HOME/Applications"
TASK_INSTALL="$(mktemp -d "$HOME/Applications/.directscan-install.XXXXXX")"
trap 'rm -rf -- "$TASK_INSTALL"' EXIT
ditto "$SOURCE" "$TASK_INSTALL/Epson DirectScan Beta.app"
codesign --verify --strict "$TASK_INSTALL/Epson DirectScan Beta.app"
if [[ -d "$DEST" ]]; then
  TASK_BACKUPS="$HOME/Library/Application Support/Epson DirectScan/Build Backups"
  mkdir -p "$TASK_BACKUPS"
  TASK_BACKUP="$TASK_BACKUPS/DirectScan-$(/usr/bin/uuidgen).zip"
  ditto -c -k --sequesterRsrc --keepParent "$DEST" "$TASK_BACKUP"
  [[ -s "$TASK_BACKUP" ]] || { echo 'Backup failed.' >&2; exit 1; }
  mv "$DEST" "$TASK_INSTALL/Previous.app"
  printf 'Previous native build preserved: %s\n' "$TASK_BACKUP"
fi
if ! mv "$TASK_INSTALL/Epson DirectScan Beta.app" "$DEST"; then
  if [[ -d "$TASK_INSTALL/Previous.app" ]]; then
    if ! mv "$TASK_INSTALL/Previous.app" "$DEST"; then
      trap - EXIT
      printf 'Previous build retained at %s/Previous.app\n' "$TASK_INSTALL" >&2
    fi
  fi
  exit 1
fi
printf 'Installed %s\n' "$DEST"
