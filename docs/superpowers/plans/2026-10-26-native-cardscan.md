# Native Epson DirectScan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** A local menu-bar Mac app that saves corrected JPGs from the Epson button.

**Architecture:** Swift/AppKit menu and ImageCaptureCore device adapter. A small
hardware-independent policy gates button-triggered jobs; private staging and a
non-overwriting exporter preserve uncertain output. No ScanSmart UI automation.

**Tech Stack:** Swift 5 language mode, macOS 13+, AppKit, ImageCaptureCore, ImageIO,
Foundation, Swift Package Manager/Swift Testing, system signing tools; no dependencies.

**Spec:** ../specs/2026-10-26-native-cardscan-design.md (user approved).

## Global Constraints

- Existing project directory on new feat/native-directscan branch, local only.
- App: Epson DirectScan Beta; separate bundle ID and private settings store.
- ES-C320W USB only, JPG/300 dpi/RGB/single sided; three corrections on by default.
- Only a confirmed physical scan-button event can initiate a scan while ready.
- No scan on startup, paper insertion, reconnect, settings or repeated busy events.
- No Accessibility, System Events, telemetry, cloud or bundled Epson software.
- Preserve the legacy helper; pause it during native tests; no public release.

## Review Focus

- Double/late button callbacks must not queue scans or publish to a changed folder.
- Full/unwritable/disappearing destination must preserve all unexported originals.
- Restart/disconnect during a scan must show recovery instead of replaying work.
- Existing files, including racing creation, must never be replaced.
- Only complete decodable JPEGs in the current staging job may be exported.

### Task 1: Settings, job policy and safe file handoff

**Files:** native/Package.swift; native/Sources/DirectScanCore/{Settings,ScanPolicy,ScanStorage}.swift;
native/Tests/DirectScanCoreTests/{PolicyTests,StorageTests}.swift.

**Interfaces:** Settings(destination: String?, paused: Bool, crop: Bool, deskew: Bool,
rotate: Bool); ScanPolicy.buttonPressed() -> Bool, ready(), fail(), disconnect();
ScanStorage.beginJob(settings:) -> Job; publish(source:job:) -> URL; finish(job:).
Job freezes its destination/settings and uses a UUID directory and filename stem.

- [x] Write tests first: button accepted only in ready, busy/repeated events rejected,
  disconnect/error never replays; settings snapshot stable; unknown/corrupt settings
  error; valid JPEG publishes; invalid/truncated/outside-stage input refused;
  collision/race cannot replace an existing file; failed destination retains source;
  interrupted job requires recovery on restart.
- [x] Run swift test --package-path native; observe missing implementation failures.
- [x] Implement only the specified policy and storage. Use ImageIO eager decode and
  JPEG marker/status checks, a hidden exclusive temporary file in the destination,
  and renamex_np(RENAME_EXCL) for atomic publication. Settings writes private/atomic.
- [x] Run full native suite; expect all pass; commit core/tests.

### Task 2: Epson device adapter and physical button route

**Files:** native/Sources/EpsonDirectScan/ScannerController.swift, DriverCorrections.swift;
native/Tests/DirectScanCoreTests/DriverConfigurationTests.swift as appropriate.

**Interfaces:** scanner status callback; start(settings:), pause(), reconnect();
snapshot settings at accepted button; use Task 1 storage for each delivered page.

- [x] Finish bounded button feasibility tests, logging actual callbacks and the
  launch of competing Epson programs. Document the supported button mechanism.
  A no-event result is a blocker, not permission to claim button support.
- [x] Test correction-option validation and driver readback rejection, timeout and
  disconnect behavior; observe red first for new behavior.
- [x] Implement browser/session/feeder lifecycle after readiness; select exact USB
  model, configure 300 dpi and requested vendor features, scan only on accepted
  button; publish each callback and complete only after successful job completion.
- [x] Add bounded readiness/scan timeout, backoff for idle discovery, session release
  on pause/sleep/quit, stale callback guards; never auto-retry a scan. Run native
  tests and build; commit only after the required button route is honestly known.

### Task 3: Menu-bar UI and local app bundle

**Files:** native/Sources/EpsonDirectScan/{main,AppDelegate,AppMenu,Diagnostics}.swift;
native/Resources/Info.plist; scripts/{build-native,install-native}.sh; .gitignore.

**Interfaces:** AppDelegate owns settings/store/controller and an NSStatusItem;
NSOpenPanel chooses destination; menu actions update next-job settings only.

- [x] Add tests for menu-driven settings persistence where behavior matters and for
  invalid configuration; run red first. No tests that merely assert UI copy.
- [x] Implement German status/menu, folder picker/open, three correction toggles,
  pause/reconnect/recovery folder, last result and quit; disable mutation while busy.
  LSUIElement app with no Dock window; bounded private diagnostics. Optional login
  control only if reliably supported; leave it off and document if omitted.
- [x] Build ad-hoc signed native app, verify Info.plist/signature, install separate
  ~/Applications bundle. Start only after old helper is paused and scanner free.
- [x] Inspect actual menu/folder picker through CUA; verify saved settings and state.
  Run native tests and commit app/build scripts.

### Task 4: Acceptance, documentation and whole-branch review

**Files:** README.md; docs/NATIVE.de.md; docs/VALIDATION.md; CHANGELOG.md;
SECURITY.md; CI workflow when applicable.

- [x] Run legacy 64 tests and native suite, build/signature check. Read all failures.
- [x] Hardware: one corrected card from physical button with Mac in background;
  second fresh card verifies rearming; choose separate test output folder and prove
  output there; pause releases scanner. Keep test files/evidence private.
- [x] Document install/start/use/recovery/rollback, exact tested limits, driver/button
  requirements and missing notarization. Do not claim unsupported models/platforms.
- [ ] Request one fresh whole-branch code review; fix important issues with a failing
  regression test then run suites/build. No public push/merge/release.
- [ ] Leave local app usable if accepted; retain fallback and its settings. Report
  actual hardware results and any unresolved button blocker without false success.

## Hardware-driven architecture adjustment — 2026-10-27

The ICA callback/KVO button route failed even with loaded paper. The installed
Epson Scanner.framework 6.7.84 delivered physical button1 in an isolated probe.
Use a separate guarded Objective-C button receiver (no scanner commands), require
its confirmed close and process exit, then run one authorized ICA scan in a fresh
process of the app. The existing tested staging/publishing/recovery logic remains
in that worker. Require worker completion+close+exit before rearming. Both workers
watch for parent death. Never redistribute Epson binaries or alter vendor files.

31 native tests passed, including real live-process message delivery and malformed
frames, helper handoff/cancellation/close ordering, frozen settings, and worker
readiness. Two button scans passed with the Mac untouched; the second used a newly
selected folder, followed by restoration of the original folder. Folder changes
also proved pause/release/reconnect. Longer uninterrupted series and login remain
outside this limited acceptance.

Idle disconnection shows an error and requires explicit reconnect, rather than
unverified background retry of the internal driver. Optional login registration
remains manual. A fresh review of this new architecture is needed because the
previous review covered the superseded ICA-only button implementation.
