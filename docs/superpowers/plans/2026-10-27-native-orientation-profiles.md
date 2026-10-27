# Orientation and scan profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add editable physical scan profiles, explicit rotations and shared duplex orientation decisions to the native Mac app.

**Architecture:** Keep capture in the existing isolated adapters. Preserve received originals, then prepare immutable processed copies with a durable journal before the existing atomic export. Use shared Swift/CoreGraphics/Vision processing; a dedicated export worker keeps continuous-collection processing out of the menu UI.

**Tech Stack:** Swift 5.9+, macOS13+, Foundation, Vision.fast, CoreGraphics, ImageIO, existing Objective-C Epson6.7.84 adapter.

**Spec:** `docs/superpowers/specs/2026-10-27-native-orientation-profiles-design.md` (approved by user27October2026).

## Global Constraints

- Existing checkout/branch `feat/orientation-scan-profiles`; no new worktree requested.
- Entire Toploader including transparent edges; physical mm before rotation,300dpi; no image stretching.
- Four fixed clockwise rotations, separate scanner-side values, fixed fallback on uncertain OCR.
- Shared duplex inference must work with the readable face on either scanner side.
- Never assume a physical driver mapping; uncalibrated duplex uses visible fixed fallback until hardware acceptance.
- Fixed width/automatic height stays explicitly unavailable until the driver case is verified.
- Preserve old settings/jobs, output grouping, recovery and receipt invariants; no duplicate rotations or overwrite.
- No private images/OCR text in tracked fixtures or production logs. No install/publication in this implementation authorization.

## Review Focus

- Crash after processing but before export: originals and processing journal permit retry without double rotation (Task2).
- Strong contradictory OCR on two sides: fallback for the whole pair (Task1).
- Invalid or oversized profile values: refuse before transport, never silently clamp (Task1/3).
- Stop during processing/late helper messages: no restart or post-cancel publication, preserve recovery (Task3).
- Settings migration with paused/job/recovery state: backup exact old bytes, preserve old Epson behavior (Task1/2).

---

### Task 1: Profiles, physical geometry and orientation decisions

**Files:** new `DirectScanCore/ScanProfile.swift`, `OrientationDecision.swift`; modify `Settings.swift`, settings migration in `ScanStorage.swift`; tests `ProfileTests.swift`, `OrientationTests.swift`.

**Interfaces:** `ScanProfile: Codable, Equatable` with area and orientation settings; `ScanSettings.activeProfile`, `driverCrop`, `driverRotate`, `requiresImageProcessing`; `DuplexMapping` maps clockwise A to B; `OrientationDecision.resolve(front:back:mapping:fallback:)` consumes four scored candidates per side and returns rotations plus a notice.

- [ ] Write tests for schema2/1 migration, round-trip profile selection, bad IDs/nonfinite/out-of-range dimensions, centered scan rectangles, both mapping signs/offsets and swapped readable faces, ties/conflict/no mapping fallback.
- [ ] Run `scripts/test-native.sh`, observe failures caused by missing behavior.
- [ ] Implement types and schema3 decoding/backup, retaining legacy behavior when no profile is selected. Four candidate scores use minimum12/two lines/20% margin. Explicit strong individual disagreement forces fallback.
- [ ] Run native suite: all existing and new tests pass. Commit `feat: add scan profiles and paired orientation policy`.

### Task 2: Local image processing and durable retry

**Files:** new `DirectScanCore/PageProcessing.swift`, `VisionOrientation.swift`; modify `ScanStorage.swift`, `Package.swift`; tests `ProcessingTests.swift`.

**Interfaces:** `ScanStorage.prepareImages(job:analyze:onProgress:)` prepares journaled copies from originals; `processingNotice(job:)` reports fallback; `export` uses prepared manifest; `VisionOrientation.analyze(_:)` returns four scores using thumbnails<=1200px, fast mode and bounded cancellation. `PageRotation.write` rotates actual pixels, preserves300dpi, normalizes EXIF and refuses overwrite.

- [ ] Write/run RED tests for marker-pixel90/180/270 rotations, no-op byte preservation, PDF dimension swaps, real journal retry after prior export, input mutation detection, interrupted copy/orphan handling and missing pair recovery.
- [ ] Implement original and processed fingerprints in a complete processing record; deterministic original input, unique output files, journal before publication. Preserve incomplete originals in existing recovery handling. OCR failures/time budget use visible fallback; IO failures remain errors.
- [ ] Run native suite green; run the new production analyzer against the three private spike inputs with ordinary local Vision access, retain private report. Commit `feat: process page pairs with durable rotation receipts`.

### Task 3: Driver adapters, export worker and native settings UI

**Files:** modify `ScannerController.swift`, `ScanCoordinator.swift`, `NativeHelper.swift`, `AppMain.swift`, `ScanWorkerMain.swift`, `EpsonFeedingWorker.m`; new `ExportWorkerMain.swift`, `ProfilePanel.swift`; modify `AppDelegate.swift`; extend adapter/handoff tests.

**Interfaces:** profile mm area is centered and checked against driver readback; disable auto crop for fixed area and driver rotation for fixed/Vision. New `HelperRole.export(ScanJob)` uses the main executable `--export-worker`; progress/notice/file/complete/closed frames follow existing validated protocol. Profile panel returns a validated settings snapshot through one save callback.

- [ ] RED tests for effective driver flags/geometry, export handoff after confirmed scanner closure, invalid progress/notice frames, pause/cancel during processing and continued liveness without restart.
- [ ] Wire isolated processing into both scan paths. Legacy continuous exports retain their existing path. New postprocessing collection exports run in a worker with lease, parent binding and existing cancel/timeout behavior.
- [ ] Add compact profile chooser/editor with name, auto/fixed area, mm width/height, mode, front/back angles, optional printed-back offset and clear uncalibrated/unsupported hints. Migration keeps previous active behavior.
- [ ] Native suite green, build signed local candidate. Commit `feat: expose scan profiles and background duplex processing`.

### Task 4: Verification, documentation and independent review

**Files:** `docs/NATIVE.de.md`, `docs/VALIDATION.md`, `CHANGELOG.md`, native `Info.plist`; implementation ledger.

- [ ] Run full native and legacy/distribution suites and build candidate. No physical scanner or installed app is manipulated by those checks.
- [ ] Document actual software verification, small OCR sample, accurate-mode host failure, unverified physical geometry/fixed-width-auto-height gates and pending hardware acceptance; no fabricated calibration descriptor.
- [ ] Dispatch one fresh whole-branch reviewer against spec/plan/diff/ledger. Address important findings with failing regression then passing suite. Preserve minor findings explicitly.
- [ ] Commit, keep local feature branch for the user and report exact outstanding hardware gates. Do not merge, publish, install or delete branches without the relevant request.
