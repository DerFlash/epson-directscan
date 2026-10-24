#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/build/ScanSmart AutoSave Beta.app"
DEST="$HOME/Applications"
REPLACE=false
while (($#)); do
  case "$1" in
    --replace) REPLACE=true; shift ;;
    --destination) [[ $# -ge 2 && "$2" = /* ]] || { echo 'Destination must be an absolute directory.' >&2; exit 2; }; DEST="$2"; shift 2 ;;
    *) echo "Usage: $0 [--replace] [--destination /absolute/directory]" >&2; exit 2 ;;
  esac
done
[[ -d "$SOURCE" ]] || { echo 'Build the app first.' >&2; exit 1; }
/usr/bin/codesign --verify --strict "$SOURCE"
TARGET="$DEST/ScanSmart AutoSave Beta.app"
if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  $REPLACE || { echo 'Target exists. Quit all helpers first; use --replace for this target.' >&2; exit 1; }
fi
# Never replace a running copy. Other predecessor helpers must be quit manually.
while IFS= read -r command; do
  case "$command" in
    *"$TARGET/Contents/MacOS/"*) echo 'Quit the installed helper before replacing it.' >&2; exit 1 ;;
  esac
done < <(/bin/ps -ax -o command=)
mkdir -p "$DEST"
TEMP="$(mktemp -d "$DEST/.scansmart-install.XXXXXX")"
trap 'rm -rf -- "$TEMP"' EXIT
/usr/bin/ditto "$SOURCE" "$TEMP/ScanSmart AutoSave Beta.app"
/usr/bin/codesign --verify --strict "$TEMP/ScanSmart AutoSave Beta.app"
if [[ -e "$TARGET" || -L "$TARGET" ]]; then rm -rf -- "$TARGET"; fi
/bin/mv "$TEMP/ScanSmart AutoSave Beta.app" "$TARGET"
printf 'Installed %s\nLaunch manually. A rebuilt ad-hoc app may need renewed Accessibility and Automation permission. Never run two helpers.\n' "$TARGET"
