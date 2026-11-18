# Separate documents implementation plan

> **For agentic workers:** Use superpowers:executing-plans task-by-task. Steps use checkbox syntax.

**Goal:** Detect and export separate documents from one captured page as an opt-in named-profile feature.
**Architecture:** Vision rectangle detection and conservative geometry selection feed Core Image crops. A separate verified one-to-many journal feeds the existing receipt-based exporter. Full source scans are privately retained.
**Tech Stack:** Swift, macOS 13+, Vision, Core Image, ImageIO, CoreGraphics, AppKit; no new dependencies.
**Spec:** docs/superpowers/specs/2026-11-18-separate-documents-design.md

## Global constraints

- Default off; old settings, pending jobs and standard card/holder behavior remain readable and unchanged.
- Keep private receipts local; preserve cancellation, leases, exclusive publication and full-source recovery.
- Support both existing duplex-switch values; never guess an ambiguous back correspondence.
- Carrier sheet hardware acceptance remains pending delivery; use synthetic images and the app UI for current acceptance.

## Review focus

- Nested table/sleeve rectangles must not become duplicate or missing receipts.
- Degenerate, overlapping or unbounded regions must never authorize unsafe crops.
- Interrupted processing/export must retain originals and avoid duplicate publication on retry.
- Saved settings from older builds and inactive profiles must preserve their values.
- Grouping must obey the user's duplex choice and never silently associate unrelated sides.

### Task 1: Document detection and pixel crops

**Files:** new native/Sources/DirectScanCore/DocumentDetection.swift; new native/Tests/DirectScanCoreTests/DocumentDetectionTests.swift.
**Interfaces:** DocumentRegion normalized four corners; DocumentDetection.detect(_:); conservative DocumentDetection.select(_:); DocumentDetection.write(input:region:output:).

- [x] Write real-image detector and geometric/pixel regression tests; run and observe failure.
- [x] Implement bounded Vision detection, geometry validation/deduplication and Core Image perspective crops.
- [x] Run the focused tests and complete native suite; inspect results; commit.

### Task 2: Per-profile setting and editor/menu

**Files:** ScanProfile.swift, Settings.swift, ProfilePanel.swift, AppDelegate.swift; profile and real AppKit tests.
**Interfaces:** optional ScanProfile.separateDocuments with an effective false default, ScanSettings.separatesDocuments; raw capture correction choices preserve the full page.

- [x] Add failing persistence/default/profile-switch and editor/menu tests.
- [x] Implement the option and appropriate control dependencies from the confirmed grouping behavior.
- [x] Verify legacy/default settings and raw capture choices; run the full suite; commit.

### Task 3: Verified separate-document processing and publication

**Files:** new DocumentProcessing.swift; ScanStorage.swift, PageProcessing.swift, relevant worker/coordinator notices; output/processing/integration tests.
**Interfaces:** verified derived manifest and processing notices; full-source archive on successful split completion.

- [x] Record the existing duplex-switch behavior and conservative association rule in the spec and ledger.
- [x] Add failing real export, source-retention, retry/cancellation/collision and old-job regressions.
- [x] Implement one-to-many journals, independent orientation, grouping and conservative fallback/recovery; keep source validation intact.
- [ ] Run focused and full checks; release build; independent final branch review and fixes.
- [ ] Document behavior/limits; PR, checks, merge, post-merge checks/branch cleanup and install the updated app; verify saved profiles and UI.
