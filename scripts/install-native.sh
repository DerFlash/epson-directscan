#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/build/Epson DirectScan Beta.app"
DEST="$HOME/Applications/Epson DirectScan Beta.app"
[[ $# == 0 ]] || { echo 'Usage: install-native.sh' >&2; exit 2; }
[[ -d "$SOURCE" ]] || { echo 'Build the native app first.' >&2; exit 1; }
[[ ! -e "$DEST" && ! -L "$DEST" ]] || { echo 'Installed native app exists; quit and preserve it before replacement.' >&2; exit 1; }
codesign --verify --strict "$SOURCE"
mkdir -p "$HOME/Applications"
TASK_INSTALL="$(mktemp -d "$HOME/Applications/.directscan-install.XXXXXX")"
trap 'rm -rf -- "$TASK_INSTALL"' EXIT
ditto "$SOURCE" "$TASK_INSTALL/Epson DirectScan Beta.app"
codesign --verify --strict "$TASK_INSTALL/Epson DirectScan Beta.app"
mv "$TASK_INSTALL/Epson DirectScan Beta.app" "$DEST"
printf 'Installed %s\n' "$DEST"
