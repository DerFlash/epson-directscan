#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_TOOLCHAIN="$(cd -- "$(dirname -- "$(xcrun --find swiftc)")/.." && pwd)"
EXTRA=()
for TASK_MACRO in "$TASK_TOOLCHAIN/lib/swift/host/plugins/testing/libTestingMacros.dylib" "$TASK_TOOLCHAIN/lib/swift/host/plugins/libTestingMacros.dylib"; do
  if [[ -f "$TASK_MACRO" ]]; then
    EXTRA=(-Xswiftc -load-plugin-library -Xswiftc "$TASK_MACRO")
    break
  fi
done
swift test --package-path "$ROOT/native" --disable-xctest "${EXTRA[@]}"
