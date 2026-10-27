#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_CALLBACK_BUILD="$(mktemp -d)"
trap 'rm -rf -- "$TASK_CALLBACK_BUILD"' EXIT
clang -fobjc-arc -mmacosx-version-min=13.0 -framework AppKit -framework IOKit -framework ImageIO \
  "$ROOT/native/TestsSupport/EpsonFeedingCallbacks.m" "$ROOT/native/Sources/EpsonImageProcessing/EpsonImageProcessing.m" \
  -o "$TASK_CALLBACK_BUILD/FeedingCallbacks"
"$TASK_CALLBACK_BUILD/FeedingCallbacks" >/dev/null
TASK_TOOLCHAIN="$(cd -- "$(dirname -- "$(xcrun --find swiftc)")/.." && pwd)"
EXTRA=()
for TASK_MACRO in "$TASK_TOOLCHAIN/lib/swift/host/plugins/testing/libTestingMacros.dylib" "$TASK_TOOLCHAIN/lib/swift/host/plugins/libTestingMacros.dylib"; do
  if [[ -f "$TASK_MACRO" ]]; then
    EXTRA=(-Xswiftc -load-plugin-library -Xswiftc "$TASK_MACRO")
    break
  fi
done
swift test --package-path "$ROOT/native" --disable-xctest "${EXTRA[@]}"
