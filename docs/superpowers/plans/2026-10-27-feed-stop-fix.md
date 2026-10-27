# Failed Pickup and Stop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve issue #3 without losing pages or replaying capture, install and retest locally.

**Architecture:** Correct ICA empty/cancel completion in the isolated worker. Keep parent ownership and confirmed-release barriers. Bound active-batch stalls separately from continuous paper waiting.

**Tech Stack:** Swift, ImageCaptureCore, existing Epson helper, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-27-feed-stop-fix-design.md`

## Global Constraints

- Existing branch and checkout; no publish, push, merge or vendor binary distribution.
- 300 dpi RGB, existing corrections/duplex/formats/settings and login registration.
- No automatic scan retry. Discard only metadata-only empty jobs after confirmed close.
- 15 seconds without a validated page during capture; 12 seconds to confirm cancellation.

## Review Focus

- Unknown partial files despite a zero-page manifest must survive and block rearming.
- A real error with the same numeric cancellation code in another domain remains an error.
- Missing/failed close must never discard a job or rearm the scanner.
- A partial ordinary duplex scan must retain originals and require explicit recovery.
- Continuous paper waiting and valid progressing batches must not hit the pickup guard.

### Task 1: Completion, pickup guard and regression coverage

**Files:** `ScannerController.swift`, `ScanWorkerMain.swift`, `ScanCoordinator.swift`, `PageManifest.swift` if a new finish reason is needed, `AdapterTests.swift`, `HandoffTests.swift`, native `Info.plist`, native guide and validation record.

**Interfaces:** Controller exposes an empty-result reason to the worker; worker emits a validated empty-reason value after release; parent retains that notice through receiver readiness. Parent finishes a stalled continuous batch through the existing finish signal, with the finish reason recorded in its job manifest.

- [ ] Add fake loaded-feeder fixtures and regression tests for empty nil-error completion, ICA cancellation/domain mismatch, unknown files, partial duplex, progress cancellation/reset/timeout and close failures. Tests assert real manifests, output directories and policy outcomes.
- [ ] Add parent tests for validated empty notices, close+exit ordering, malformed values, continuous active-batch stall and unlimited idle waiting.
- [ ] Run `bash scripts/test-native.sh`; expect the new behavioral assertions to fail on the old implementation. Record failures.
- [ ] Implement the smallest fixes matching the spec, bump build 12 and update the user guide.
- [ ] Run `bash scripts/test-native.sh`, `bash scripts/test.sh` and `bash scripts/build-native.sh --replace`; expect all tests and signed build validation to pass.
- [ ] Commit locally; obtain the required independent final code review and resolve important findings with failing regressions first.

After code review, preserve the existing private empty failed job through the
recovery UI, quit the old app, install with `scripts/install-native.sh --replace`
and read back version/signature/settings/readiness. Request physical tests only
when the app is ready. Record actual results and remaining hardware limits; do
not mark issue #3 complete before the device retest.
