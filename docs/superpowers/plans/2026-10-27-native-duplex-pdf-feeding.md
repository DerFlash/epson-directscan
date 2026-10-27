# Native Duplex, PDF and Automatic Feeding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement inline task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add switchable duplex JPG/per-card PDF and true automatic-feeding collection PDF, install locally and test with the Epson.

**Architecture:** Preserve the ordinary ICA worker. Add an isolated Epson automatic-feeding worker using the installed driver, sharing the scanner OS lease. Both paths stage validated pages into a durable job manifest; output is published exclusively only when its grouping is complete. Parent coordinator owns session state and mutable UI locks.

**Tech Stack:** Existing Swift/AppKit/ImageCaptureCore/ImageIO plus Apple PDF APIs and guarded Objective-C Epson 6.7.84 runtime bridge. No downloaded runtime or redistributed Epson binaries.

**Spec:** ../specs/2026-10-27-native-duplex-pdf-feeding-design.md (explicitly approved).

## Global Constraints

- Existing checkout, new feat/native-duplex-pdf branch, local installation only.
- ES-C320W USB, 300 dpi RGB; preserve selectable crop, deskew and rotation.
- Duplex: separate JPGs per side or one PDF per card; automatic feeding: one collection PDF.
- True automatic insertion after one physical start; physical Epson Stop or configurable inactivity ends the session.
- Timeout choices30/60/120/300 seconds or unlimited if accepted; default120. Never time out an active transfer as idle.
- No startup/insertion scan outside an explicitly active session; no blind retries, replacements or silent correction downgrade.
- Preserve OS lease/confirmed close+exit sequencing, retained pages and stable app/login path. Back up settings before migration.

## Review Focus

- Stop during the final duplex card: complete pages survive, incomplete pairing is visible and never misrepresented.
- Destination loss, collision or failed PDF write: original pages and recovery manifest survive.
- Crash after PDF publication but before acknowledgement: recovery never replaces or silently duplicates output.
- Late worker callbacks/session timeouts cannot append to a new collection or resume after stop.
- No-limit idle collection must not hit the old130/140s worker deadlines or unbounded in-memory image accumulation.

### Task 1: Verify Epson automatic-feeding and page contract

**Files:** private diagnostic only under ../../outputs/epson-scan-automatik/automatic-feeding-test/; findings in this plan's ignored ledger.

**Produces:** verified runtime signatures, legal mode/color/image values, side/page metadata, complete image extraction path, correction configuration and stop/timeout callback ordering consumed by Task3. No implementation may claim these based solely on method presence.

- [ ] Pause the existing app through its UI and confirm its lease is free. Use an isolated, lease-owning diagnostic with version/ABI checks and parent-death cleanup. First query capability objects without starting a scan.
  Expected: real device reports duplex/auto-feeding support and usable settings; diagnostic closes normally and leaves no competing owner.
- [ ] After one expendable card is ready, test the native automatic-feeding entry point and image callbacks. Persist diagnostic pages privately. Keep the receiver running until the user's physical Stop rather than expiring before their response.
  Expected: two complete sides, another insertion scans without a second Start, physical Stop ends, and a short idle timeout ends separately. Validate actual images and correction path.
- [ ] Record exact callback/signature/side ordering and update only technical choices in ledger. If this gate fails, diagnose the concrete cause; do not build a manual-per-batch substitute. Diagnostic is throwaway, not shipped product code; physical evidence is its check.

### Task 2: Settings, validated pages and PDF transactions

**Files:** DirectScanCore/Settings.swift, ScanStorage.swift; new PageManifest.swift and PDFOutput.swift; tests Settings/PDF/Storage.

**Interfaces:** ScanSettings adds duplex:Bool, outputFormat:OutputFormat(.jpg/.pdf), automaticFeeding:Bool, feedingTimeoutSeconds:Int(0/30/60/120/300). Existing JSON migrates with original choices intact. PageManifest records ordered ValidatedPage(index,sheet,side,sourceName,width,height) and job completion. PDFOutput.write(pages:[URL],to:URL,dpi:Double) validates page count/geometry before return. ScanStorage stage/complete/export APIs retain original files until verified publication and preserve export receipts.

- [ ] Add failing tests for legacy migration/defaults/corruption, original-settings backup, exact duplex pairing, PDF2-page order/geometry, incomplete JPEG/pair refusal, collection preservation and exclusive collision/export receipts. Use real generated JPEG fixtures and actual PDF parsing/rendering.
  Run scripts/test-native.sh; Expected: new assertions/API fail, established tests remain understood.
- [ ] Implement the smallest versioned settings/manifest and bounded-memory PDF writer. Keep JPEG eager completeness checks; use private temporary output and renamex_np(RENAME_EXCL), preserve receipts before deleting source. Recovery may explicitly export confirmed pages without resuming a scan.
- [ ] Run native suite; Expected: all pass. Commit core/settings/output changes.

### Task 3: Duplex scan and automatic-feeding session worker

**Files:** ScannerController.swift, ScanWorkerMain.swift, NativeHelper.swift, ScanCoordinator.swift; new native/Helpers/EpsonFeedingWorker.m; session-policy tests and fake adapter tests.

**Consumes:** Task1 verified runtime contract; Task2 settings, page manifest and PDF publication APIs.
**Produces:** ordinary worker emits validated page/output events and final completion. Automatic worker emits session-ready/waiting/page/session-ended/error/closed with bounded frames. SessionEndedReason is stop/idleTimeout/error; only the first two authorize normal collection finalization. App finish request uses an explicit control channel or graceful stop request, not a fabricated hardware event.

- [ ] Write failing tests for duplex support/readback, two-side accounting, session snapshot, insertion only while active, idle deadline reset and active-transfer exclusion, physical/app stop distinctions, late callbacks, no-limit deadline, partial last card, interrupted/recovered session, and close/lease ownership. Retain the existing surviving-child regression.
  Run scripts/test-native.sh; Expected: new behavior fails first.
- [ ] Enable ICA duplex from settings and stage ordered sides before grouping. Implement the guarded automatic worker from Task1's proven mechanism, holding scanner.lock throughout waiting/scanning/close. Apply and confirm all enabled corrections through installed Epson processing components. Keep only one scanner owner.
- [ ] Extend coordinator/protocol for active collection and final PDF commit. Preserve existing backpressure/frame validation; replace whole-session hard deadlines with readiness/active-transfer guards plus the chosen idle timeout. No auto-replay after error or restart.
- [ ] Run native suite and native build; Expected: all pass, helper/main signatures valid, no device actuation by tests. Commit worker/coordinator changes.

### Task 4: Menu, migration, installation, recovery and acceptance

**Files:** AppDelegate.swift, Info.plist, build/install scripts, docs/NATIVE.de.md, VALIDATION.md, SECURITY.md, CHANGELOG.md; mode/persistence tests where behavioral.

**Consumes:** Task2 settings and recovery; Task3 coordinator state/actions.

- [ ] Add German duplex/format/automatic-feed/timeout choices and active collection page count, finish action and recovery export. Freeze setting mutations during a session. Closing status keeps it running; quitting offers save or retain. Preserve existing login registration and stable bundle ID/path.
- [ ] Run native and legacy suites, build/plist/deep signature and ABI checks. Expected: all pass. Save the current installed app/settings before replacing, confirm no active scan, install locally through existing installer.
- [ ] Hardware: use one expendable card repeatedly. Verify duplex JPG sides,2-page per-card PDF, automatic reinsertion without Start and collection PDF ending by Epson Stop; also short idle timeout. Inspect all PDF pages/order/rendering, destination, pending/recovery and rearming. Retain private evidence and report actual limits.
- [ ] Obtain one fresh whole-branch review; grade findings, one RED→GREEN fix pass for Important/Critical, then full relevant checks. No re-review loop. Commit corrections and acceptance docs.
- [ ] Leave the installed app usable, keep feature branch/fallback and login item; preserve private evidence. No publish/merge/PR. Follow existing inline execution without a further approval pause: user has expressly approved this design and local implementation/install/test.
