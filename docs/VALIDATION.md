# Download release validation — v0.3.0-beta.2

> Current local development work: see “Transparent-holder correction, build20”
> at the end. Published beta2 remains unchanged.

The repository was renamed in place to `DerFlash/epson-directscan` (same repository
ID, issues, releases and history; old URL redirect verified). Beta2/build15 adds
an arm64 app DMG/ZIP and canonical download/update guidance. It is explicitly
ad-hoc signed and not notarized, as chosen by the owner; no signing credentials,
security bypass or Epson binaries are included. The existing installation is not
replaced by this packaging work. Capture/storage/helper sources are unchanged.

Package regressions exercised actual DMG creation/read-only mounting and ZIP
extraction with a synthetic signed app: bytes/signatures/executable permissions,
Applications link, exact checksums, wrong bundle/damaged helper rejection,
existing output preservation and refusal of an ad-hoc app when notarization is
required. A RED case found publisher-only permissions; the package copy now
receives public read/execute access while source permissions remain unchanged.
Final local checks: 70 native +26 Node +42 Python tests passed (138 total),
including 4 distribution tests. Native and legacy builds pass. The real beta2 DMG
was mounted read-only, its Applications link/readable installation notes checked,
and its app copied to a temporary folder. DMG/copied/ZIP app files match the
signed build byte for byte; all signatures, executable permissions and checksums
pass. Its 5 app files contain no private home/temp build paths or bundled vendor
frameworks. All Mach-O __TEXT sections in all 3 executables match installed,
hardware-tested build14; removal of debug symbol paths and signing/metadata do
not alter executable logic. Local Gatekeeper assessment does not approve the
ad-hoc copy (exit 3); no notarization or security exception was claimed/applied.
No installed app was replaced or launched for the packaging check. Remote CI,
upload/download verification and publication are recorded in the release/PR.

## Prior tested native release

# Release validation — v0.3.0-beta.1

The native source release promotes the tested build14 logic. Only its bundle
version label changes from `0.3.0-beta.1-dev` to `0.3.0-beta.1`; no capture,
correction, storage or recovery behavior changes for publication. Local acceptance
and earlier development evidence follow chronologically. Historical “local only”
statements describe those development stages, not the release authorization.
The release adds native core/helper tests and compilation to CI. Its ordinary
hosted runners have no Epson hardware/driver, so the Epson orientation integration
case is gated; the local 134-test result includes the installed-driver test.

Release preflight: all70 native +26 Node +38 Python tests pass (134 total),
the native callback harness passes, and both native and legacy signed builds pass.
Executable bytes outside the embedded ad-hoc signing data match the installed,
hardware-tested build14 byte for byte. The changed Info.plist version changes the
embedded signing hash, so the full executable SHA differs as expected. Local
document links and the release tree/history privacy audit passed; no new binary
or private-path blobs exist in the previously unpublished commit history.
Source-archive and remote CI verification are recorded once published. The local
hardware record is unchanged by publication.

## Earlier development evidence

# Timing-controls development validation

This branch adds interval controls and local measurements after Beta 2. Current
input-free tests: 26 Node + 38 Python pass. The full compiled poll orchestration
is exercised with substituted GUI/runtime I/O. One paired physical single-card timing check has passed; this is not a series
throughput guarantee. The installed interval selector and timing display were
verified with real measurements.

An input-free stay-open macOS applet requested 250 ms and observed 262.0,
262.3 and 258.0 ms between idle callbacks. The 1000 ms control observed 1050.8,
1051.3 and 1050.4 ms. This verifies subsecond scheduling on this Mac; it does not
measure ScanSmart or prove a full scan's speed. The internal resource bridge
averaged 19.2 ms over eight getSettings requests with isolated test storage.

The first physical timing-controls test exported exactly one readable JPG without
Mac clicks, preserved the existing 15 JPGs and returned to ready. From the first
action poll through saved it took 14.465 seconds. Measurements identified about
2.0 seconds per Save-view capture, plus the fresh capture inside an action.
The role-specific capture optimization avoids value/name AX reads for roles
whose text is never consumed; both snapshots and all dispatch guards remain.
A second scan of the same card with that optimization took 11.891 seconds from
the first action poll through saved, 17.8% less in this paired comparison. Mean
Save-view capture time fell from 2025.673 to 1325.843 ms. Both runs used 250 ms
polling. Exactly one new complete readable JPG was verified; existing files were
unchanged by size/mtime. Hardware scan/feed time before the first action poll is
not included. These two runs are not a statistical benchmark or a long-series
acceptance. The separate read-only observer for run two expired before the user
scanned; native timestamped app records and post-scan file checks provide its
evidence.

A further targeted optimization omits the separate setDestination action when
its observed folder already exactly matches the configured folder. A fresh full
native capture, complete metadata/identity guard and target collision check still
precede Save. Changed folders retain setter/readback handling. Pure and actual
runtime tests cover direct reservation, persisted plan, changed/blocked views,
existing targets, uncertain actions, restart arming and complete JPEG confirmation.
The installed direct-Save path passed a fresh same-card USB scan: recorded
actions were only openSave and save, with no setDestination. One new complete
readable JPG was verified and all17 existing files retained their size/mtime.
First action poll through saved measured9.025s versus11.891s previously (24.1%
shorter in this comparison). Opening acknowledged through Save acknowledged
measured4.368s versus7.415s, about3.046s less. Hardware feed time is excluded;
these single-card observations are not a long-series throughput guarantee.

The preceding Beta 2 acceptance record follows for context.

# v0.1.0-beta.2 validation

This is a source beta with one successful physical single-card scan. Automated
checks cover the state machine and native bridges; hardware evidence is limited
to the exact configuration below.

| Check | Result |
|---|---|
| Pure policy and native-event guard tests | 24 passed; input posting is substituted |
| AppleScript bridge/geometry/status and real Foundation/ImageIO tests | 28 passed; isolated temporary storage, no GUI input |
| Clean macOS app build and strict local signature verification | Passed |
| Temporary installation, existing-target refusal and explicit replacement | Checked for Beta 1; release scripts retain the same install behavior |
| Shell syntax and whitespace checks | Passed |
| Independent code review | Passed after fixing counterless multi-image undercount; no open Critical/Important findings |
| GitHub-hosted CI | [Check workflow](https://github.com/DerFlash/epson-directscan/actions/workflows/check.yml) runs on pushes and pull requests |
| Physical scanner-button export | One single-card JPG export passed on 2026-10-25; remaining cases below are open |

The synthetic fixture is a 2 × 2 white image. Invalid-image cases include a
two-byte JPEG header, an interrupted real JPEG, marker-wrapped garbage and
non-image data. None may report success or trigger a repeated Save. Native
regression tests include loading the real bundled resources, null values, exact
compiled `actionId` serialization, dispatch/acknowledgment, transient capture
errors and the counterless single-image view.

## Observed hardware result

The corrected implementation at `c7f79c9` was installed and tested with:

- Epson ES-C320W connected by USB.
- Epson ScanSmart 3.7.22, German interface.
- macOS 27.0.1.

One card was scanned using the physical scanner button. The user left the Mac
untouched for 20 seconds; the helper completed both save steps. Exactly one new
JPG appeared in the configured destination. It was readable, 741 × 1033 pixels,
317150 bytes; all 13 existing JPGs retained their sizes and modification times.
The helper recorded `saving` → `verifying_files` → `saved` → `ready`.

Earlier attempts exposed the native bugs corrected in Beta 2 and required manual
recovery. They are not counted as automatic successes. After this successful run,
Beta 2 added a conservative guard: a counterless view can mean one image only
when its suffix is exactly .jpg/.jpeg. A numbered suffix without a readable page
count stays invalid. Regression tests cover this guard, a denied dispatch after
a missing counter, and the complete single-image cycle; this additional guard
has not had a further physical scan test.

This establishes one complete automatic cycle, not general production readiness.
Repeated cycles, longer scan sequences, a real export to a changed destination,
restart/login behavior, physical cancellation/error cases and unavailable
destinations remain unverified on hardware. Other versions, languages and scanner
models are untested. No real scans, private paths or state files are published.

## Remaining hardware acceptance

Before marking a device/version combination as fully tested:

1. Quit all other scan helpers. Install one beta copy and grant that copy its own
   macOS permissions. Choose a separate test destination and enable the helper.
2. Finish/cancel any pending export and let it observe ScanSmart's normal start
   screen. Scan a harmless sample with the physical scanner button and leave the
   Mac untouched. Confirm the exact expected JPG count, readable images, correct
   folder and successful app status.
3. Repeat twice to check the next scan rearms. Change the destination through the
   app, rearm from the start screen and confirm only the new folder receives files.
4. Test cancelling before Save, disabling the helper, dry run and a manually
   handled error dialog. Check that none creates an unintended file or click.
5. Test an existing expected filename and an unavailable destination. The helper
   must pause. Inspect output, resolve the cause, reset, and use a fresh scan.
6. Restart the helper while an export is pending. It must wait for you to finish
   or cancel it rather than exporting that uncertain job automatically. Verify
   any login item separately after signing in again.

Record the exact macOS, ScanSmart, scanner and connection versions with results.
Do not publish real scans, private paths or unredacted state files as evidence.


## Native DirectScan development history (0.2, local branch)

Current final build 6 acceptance is recorded at the end of this section. The
earlier ICA-only candidate and its failed button route are retained as history.

Direct ICA USB scans were verified on the same Mac and ES-C320W. With
VF_AUTOCROP=1, VF_DESKEW=true and VF_AUTOROTATE=true, the second sample produced
a readable 745x1040 JPEG at 300 dpi, 340519 bytes; requestScan to file callback
was 3.994 seconds. Input rotation/skew was not measured, so their individual
correction amounts are not established. These were prototype scans, not the new
menu-bar app's hardware acceptance.

Native software tests cover button/busy/error policy, settings, correction
readback validation, real JPEG validation and non-overwriting file handoff,
recovery preservation, and bounded system commands. A local native build and
ad-hoc signature have passed. The unchanged legacy suite still passes.

Confirmed button presses did not arrive on the tested ICA delegate/status paths,
including a full AppKit event-loop probe without Epson background helpers. A later
Mac-target probe timed out before its human confirmation; it is inconclusive.
The persistent app adds guarded observation of the existing legacy buttonPressed
property. Confirmed presses on 2026-10-27, first empty and then with a loaded card,
still produced zero button events while the app remained ready with both Epson
helpers absent. The loaded card did not feed; only the power LED briefly blinked.
The physical-button acceptance gate therefore failed for the current ICA route.
Do not claim the native app's button workflow is accepted, and do not publish it
as a working replacement until that gate passes.

Before the Epson-specific button integration, the reviewed candidate had 18 passing native tests. A deliberately
truncated real JPEG with a synthetic end marker is rejected using per-frame
ImageIO status after eager decoding. Injected scanner/service adapters verify
that delayed, failed and absent close acknowledgements do not restore Epson
services early or silently rearm. Shared connection/recovery consent is tested.
These adapters never actuate the real scanner or launch agents. A fresh legacy
26 Node + 38 Python suite and signed build also passed. Hardware acceptance of
the installed native menu-bar app has not passed. At that stage the app was installed but paused; both original Epson launch
agents were confirmed running after session release.

A pure non-scanning diagnostic found that Epson emits an intermediate selection
notification before the actual feeder (1.908 and 2.117 seconds in that run).
The adapter now ignores that intermediate state while retaining its deadline;
the regression failed before the fix and passed afterward. Build 3 was installed
with the previous local build backed up. A real pause released the session and
restored both Epson helpers. Reconnecting within the same process failed twice
with device removal followed by ICReturnConnectionFailedToOpen (-21345); a fresh
app process connected successfully. This lifecycle defect remains unresolved.

USB inspection found four vendor-specific interfaces and no HID button interface.
Epson's installed Scanner.framework contains its own interrupt/button handling;
that is a lead for a separate Epson-specific adapter, not proof of an available
public macOS API or a tested replacement. No manufacturer file or global scanner
autolaunch assignment was changed by the installed app.

### Native button handoff — 2026-10-27, local build 5

The earlier ICA button gate was resolved by a different mechanism: the installed
Epson Scanner.framework 6.7.84 delivered a confirmed physical `didPressButton:1`
callback. The app now isolates this internal driver API in its own helper, checks
the exact version and method ABI, then closes and exits the helper before starting
a fresh ICA scan process. No Epson binaries are redistributed. Early startup
signals and non-1 buttons cannot authorize a scan. The earlier within-process ICA
reopen defect is avoided by process isolation, rather than claimed fixed in ICA.

31 native tests passed, including actual subprocess streaming/ordering/invalid
frames, frozen settings, duplicate/busy/early/late button rejection, confirmed
close plus exit before scan/rearm/service restoration, retained pending files on
failure, and authorized worker readiness/empty feeder. A real long-running-child
handshake reproduced buffering until EOF with FileHandle.read(upToCount:); bounded
POSIX reads corrected it, and the full suite passed. Build/plist/deep signature
and driver compatibility checks passed.

Two single-card scans were then triggered by the physical Epson button with the
status window closed and no Mac clicks. Each yielded exactly one readable JPG;
Pending was empty afterward, and the app returned to Ready:

| Test | Destination | Image | Bytes | Accepted button to JPG / Ready |
| --- | --- | --- | --- | --- |
| First card | selected normal scan folder | 741×1037, 300 dpi | 306854 | about 6 s / 8 s |
| Second card | separately selected test subfolder | 745×1037, 300 dpi | 330105 | about 5 s / 7 s |

The second filename was absent from the original folder. All three corrections
were enabled; the first image was visually checked, upright with tight card crop.
Input skew/rotation was not independently controlled, so their individual effects
remain unquantified. Changing folders through the real picker paused/released
and reopened the button helper successfully; the original destination was then
restored. These are two cycles with a folder change between them, not a long
uninterrupted-series, sleep/wake, cancellation or login acceptance test. The additional independent review and final hardened build are recorded below. No native public release is implied.


### Final native build 6 and restart ownership regression

A fresh independent review of the new helper/process architecture found one
Important issue and no Critical/Minor findings: startup recovery could restore
Epson services while an old child was still alive or blocked in driver close.
A separate hardware-free child holding the scanner OS lock reproduced the failure
(32 tests, two failed assertions). Both real helpers now independently hold the
same exclusive flock before any hardware open, through close and process exit;
each rechecks its parent after acquisition. Service restoration and new connection
check that same lock, even without a recovery memo. A live owner blocks recovery
without removing the memo. The regression and entire native suite passed 32/32.
The unchanged legacy suite passed 26 Node + 38 Python. Release build, deep ad-hoc
signature and guarded Epson6.7.84 compatibility checks passed. One review fix pass;
no author-claimed second review.

The final installed build then passed a third physical single-card scan with the
status window closed: one event, one fully readable JPG in the original folder,
745×1037 at300dpi,293255bytes. Accepted button08:10:36Z -> JPG08:10:41Z -> Ready
08:10:43Z; Pending0. The rearmed receiver held the ownership lock. A final real UI
pause confirmed the lock free, memo absent and both original Epson services back;
reconnecting returned to Ready. Settings remain the normal destination with all
three corrections on. Installed main/helper hashes match the built artifacts.
No ScanSmart frontend was running. Source remains on the local feature branch.


### Implementation decisions and remaining limits

These decisions carry forward the execution record; no review findings remain
open, and the reviewer reported no Minor findings to defer.

1. Use bundled Swift Testing because this CLT-only Mac lacks XCTest. Cost: the
   test launcher needs the bundled macro plugin; older toolchains are unverified.
2. Replace short-lived button probes with a persistent instrumented app so human
   confirmation cannot arrive after the receiver expires. The attempted ICA/KVO
   route still failed and was removed; actual hardware acceptance remained the
   gate rather than being inferred from API availability.
3. Add an optional, closable status panel alongside the menu-bar icon. Cost: one
   extra small UI surface; it makes readiness, settings and test counts visible.
4. Use the installed Epson button API only in a guarded separate process. Cost:
   dependence on a private ABI; only checked driver6.7.84 is accepted and Epson
   binaries are never redistributed.
5. Run each accepted scan in a fresh process because same-process ICA reopening
   failed while fresh-process scans worked. Cost: small process startup overhead
   and a protocol requiring explicit ordering/cancellation tests.
6. Require manual reconnect after an idle USB interruption instead of an unproven
   background retry through the internal driver. Cost: interruptions require a
   user action; unattended reconnection is not promised.
7. Add one fresh review for the new helper architecture because the earlier
   review covered the superseded ICA button route. Cost: an additional review;
   its one Important finding was verified RED→GREEN without a further re-review.
8. Leave physical long series, sleep/wake, cancellation and login acceptance open.
   Cost: the local three-card beta acceptance does not establish those conditions
   or general production reliability.
9. Reject other scanner models and driver versions. Cost: compatibility needs
   separate work and real-device acceptance after a model or driver change.

Automatic login registration was deliberately left unchanged, as allowed by the
approved design. The branch and checkout are retained locally at the user's
request; no native release, merge or publication is part of this completion.


### macOS login registration — 2026-10-27 follow-up

At the user's request, the installed `~/Applications/Epson DirectScan Beta.app`
was added through macOS General → Login Items → Open at Login. The old ScanSmart
AutoSave Beta entry was removed from that list to prevent competing startup.
The final UI list was read back and showed DirectScan present and the old helper
absent. Existing takeover acknowledgement=true and paused=false were verified;
the running native app remained Ready/listening with the normal destination.
This verifies the saved login configuration, not an actual logout/login cycle.
No source behavior or installed app binary changed for this setup.

### Native duplex/PDF/automatic feeding — 2026-10-27 local acceptance

Local branch `feat/native-duplex-pdf`, in the existing checkout. Installed
**0.3.0-beta.1-dev, build11** uses the stable app path/bundle ID. Prior builds and
an exact private0600 schema1 settings backup remain available. Schema2 migration
preserved the original folder/corrections. Saved macOS login registration and
background permission were read back; an actual logout/login remains untested.
No native push, merge, public release or PR was authorized or performed.

| Check | Actual result |
| --- | --- |
| Duplex JPG | One physical Start produced two readable RGB/300dpi JPGs, shared card number, front/back suffixes.745×1037 and744×1034 pixels, visually inspected. |
| PDF per card | One physical Start produced one2-page PDF, front then back,300dpi and correct card-size boxes. Both pages rendered/inspected. |
| True automatic feeding | An initially loaded card was scanned after one physical Start. Reinserting the same card without another button produced a second front/back pair: four ordered complete pages with sheet/side metadata. |
| Physical Stop, final build11 | User scanned a card, waited for completion and pressed Epson Stop. The app automatically published a2-page collection PDF, journal reason `stop`, and returned Ready. No pending pages. |
| Idle timeout, final build11 | With30seconds selected, user scanned one card and neither inserted another nor pressed Stop. The app published a2-page PDF with journal reason `idleTimeout`, after34seconds total including capture, and automatically returned Ready. |
| Real recovery | Four pages retained after a PDF-validation failure were exported through the actual recovery UI as one4-page PDF, without another scan. Published grouping/receipt were checked, all four pages rendered/inspected, Pending empty. |
| Final installed profile | Duplex JPG, automatic collection off,120seconds saved for later collection use, all three corrections on, normal Documents/Scans destination, listening/Ready. |

Checks ran on the installed driver6.7.84, Apple Silicon/macOS27.0.1. The installed
main executable, both helpers and plist match the checked build; deep signature,
plist and no-device-open helper ABI checks passed. The small status panel can be
closed while the menu-bar app/listener continue running. Private images, job
receipts, source hashes and rendered output evidence are outside the repository.

#### Software verification and fixes

55 Swift tests cover real JPEG/PDF decoding/rendering, migration/backup,
exclusive output/receipts, crash reconciliation, pairing, session/idle/stop/late
messages and cross-process ownership. A separate hardware-free callback harness
compiles and invokes the exact shipped feeding receiver.26 Node and38 Python
legacy tests also pass; their fixture-only AppleScript probes do not read or
operate real application windows. The initial restricted legacy run could not
use its runtime; the rerun passed all 38 Python tests.

One independent whole-branch review found3Important issues,0Critical and0Minor.
All three received reproducing RED→GREEN tests in one fix pass: incomplete duplex
originals are retained privately, recovery grouping remains stable across a
restart, and startup finish intent prevents arming. A real subprocess test checks
distinct arm/finish signals. No re-review loop was used.

Hardware acceptance exposed two additional bugs, both fixed with regressions:

- A mandatory unconditional Epson page-begin callback was missing from the
  product receiver, although the private probe implemented it. The exact receiver
  harness reproduced that exception; page-begin/cancel/button callbacks and the
  no-open compatibility check now enforce this contract before device capture.
  The empty failed job was inspected and archived through recovery. After the
  driver crash, one reconnect stalled; a scanner power cycle restored opening.
- Quartz read177.6pt back as177.60000000000002pt. Exact equality incorrectly
  rejected an otherwise complete4-page PDF. A test using the actual cropped card
  dimensions reproduced the failure. Validation now permits0.0001pt rounding
  (<1/2000 of a300dpi pixel), while keeping page-count and readability checks.
  All four original pages survived and were recovered; the corrected physical
  Stop and idle tests then passed without manual saving.

#### Decisions and limits

1. Retain the existing checkout and a new local feature branch, following the
   prior user preference. The checkout and old native branch/build backups stay
   available; this work does not integrate or publish anything.
2. Develop independent settings/PDF storage while waiting for physical driver
   tests. This saved human waiting time; hardware acceptance stayed mandatory.
3. Use native Scanner.framework capture/crop/deskew plus Epson ImageProcessor/
   Esaod orientation. The full ScanEngine prototype visibly corrupted images and
   was discarded. This keeps the Epson detector and avoids that failing pipeline;
   compatibility remains restricted to the checked internal6.7.84 ABI.
4. Advance UI/installation before marking all driver gates complete so the real
   installed app could supply the remaining evidence. Failures retained prior
   builds/pages and were not counted as passed acceptance.
5. Overlap the one source review with pending human hardware actions. Subsequent
   review and device findings were handled by reproducing tests in the same fix
   pass; source review was never substituted for actual scanner acceptance.
6. The reviewer explicitly declined to certify pending AF/timeout hardware;
   root subsequently performed the installed insertion/Stop/idle tests above.
7. Deliberate Stop during a partially transferred card was not performed on the
   device. Software verifies completed-page retention and private preservation
   of an incomplete last sheet; actual driver cancellation ordering may still
   require explicit recovery in that corner case.
8. Final installation/GUI/signature judgment was retained by root: the installed
   About version, files/signature, settings, ready state and saved login entry
   were read back. This does not establish a logout/login cycle.

No minor findings were deferred. Long series, forced mid-transfer cancellation,
sleep/wake, logout/login, other models/driver versions and other Macs remain
unverified. A neutral inverted-text fixture returned180° and the corrected output
returned upright. Colored playing cards sometimes remain inverted, and AFM images
of this test card are darker than ordinary ICA images. These observed image-quality
limits are stated in the user instructions; no extra tone-matching feature was
added. This is a local beta acceptance, not general production certification.

### Issue #3: pickup / empty Stop correction (local build 12)

The user reported a non-feeding medium followed by physical Stop. Local evidence
showed normal ICA duplex/per-card PDF, no image files, nil-error completion into
`ScanStorage.complete`, and app-generated generic worker failure -201. No driver
error -201 was established. The metadata-only job was retained; no image output
from that failed attempt existed.

Regression tests first reproduced empty completion, missing short progress
cancellation, invalid empty protocol values and missing user notice. Additional
RED tests reproduced cancellation-notification ordering that could otherwise
publish an interrupted job, repeated notifications extending cancellation wait,
and contradictory output after an empty completion. The correction keeps empty
jobs until confirmed close, rejects any unexpected/partial files, distinguishes
only ICErrorDomain/-9924 as documented cancellation, and rearms only after
confirmed release and successful process exit. A 15s no-validated-page guard
requests cancellation (12s acknowledgement); continuous waiting between batches
is excluded. Existing progressing-page and partial-duplex retention checks pass.

Verification: 67 native Swift tests and the compiled Epson callback harness pass;
26 Node and 38 Python legacy tests pass (131 software tests total). Restricted
runs could not access compiler caches / legacy AppleScript I/O; the same tests
passed with normal local execution permissions. Release build, Epson module
compatibility check, plist lint and strict code-signature validation pass.
Build 12 is installed with an archived previous build, matching executable hash
and valid strict signature. Settings remained duplex/per-card PDF to the chosen
folder with all corrections enabled. The old metadata-only failed job was
archived through the recovery UI without replaying capture.

The first device retest reproduced failed pickup followed by physical Stop.
The driver again completed with no error and no pages. The app displayed
“Bereit – Epson-Taste drücken · Keine Seite gescannt – Vorlage und Einzug prüfen”,
rearmed its receiver and left Pending empty. No output file was created. The user
confirmed that physical Stop halted transport. The automatic guard subsequently requested cancellation after 15–16 seconds
without pages; the user confirmed that transport stopped. ICA then reported
unsolicited scanner error -9933 and the physical error light remained active.
A later power-cycle released the native button receiver (-106); the original
Epson agents resumed and ScanSmart handled the next attempt. The user and the
actual ScanSmart dialog both reported paper jam. That attempt was not a native
build13 scan and cannot validate its diagnostic instrumentation.

This is a real scanner fault, not a neutral cancellation to suppress. Build14
adds explicit paper-path/recovery and disconnected/reconnect hints while keeping
error state and retained files. All 70 native, 26 Node and 38 Python tests pass
(134 total); release build, compatibility, signature and installed/build hash
checks pass. The new hints were covered by RED→GREEN controller/handoff tests. Epson documentation requires physical paper-path
clearance; automatic USB reconnection remains outside this fix.

Final build14 device acceptance: the user confirmed a clear paper path and no
flashing error. Root closed ScanSmart, launched the installed native app and
verified readiness/profile in the real UI. One normal expendable card was then
scanned using the physical Epson button. Both sides were staged and a single
616,141-byte PDF was automatically published. Independent CGPDFDocument reading
confirmed two pages (177.84×248.88pt and178.56×248.16pt), and both pages rendered
successfully. Pending was empty; the app returned to ready/listening with one
physical button event and one saved output. Closing the status window left the
main app and its button receiver running. The original failed empty jobs remain
archived privately, and the previous application builds remain backed up.

Local acceptance of the reported workflow is complete. No deliberate repeat jam
or forced mid-image hardware cancellation was performed; retention/error cases
are covered by regression tests. Prior image-quality limits and other unverified
native-device cases remain as documented above. The source branch remains local;
GitHub issue #3 records the result and stays open pending publication/integration.

### Orientation and outside-dimension profiles — 2026-10-27 software acceptance

Local `feat/orientation-scan-profiles`, candidate **0.4.0-beta.1-dev, build 16**.
This is an implementation/software check, not new physical scanner acceptance or
a publication. The installed app was not replaced or launched by this work.

- 98 native Swift tests pass, including the explicitly enabled production Vision
  comparison with the private spike inputs; the native Objective-C callback/area
  contract harness also passes. The legacy/distribution suites pass 26 Node and 42
  Python tests. The ad-hoc native app builds and validates its helper compatibility
  without opening a device.
- Schema 1/2 exact-byte backups, preserved previous active settings, selected-profile
  round-trip, invalid dimensions/IDs, confirmed units and rejected area readback,
  explicit 300dpi pixel conversion and centering are covered by software tests.
- Pixel marker tests verify clockwise 90/180/270 output, swapped dimensions,300dpi,
  normal/omitted-normal EXIF, no-op byte preservation and no overwrite. Processed
  export retry does not rotate again; changed original bytes are rejected. A crash
  during preparation retains owned partial copies and all captured originals.
- Joint scoring handles either readable scanner side, both geometric signs/offsets,
  conflicting strong evidence, ties and missing calibration. An uncalibrated pair
  uses both fixed values with a notice and does not waste time on OCR.
- A real private comparison with two distinct card fronts in four digital rotations
  reproduced 8/8 correct front decisions using the product analyzer. Four back-only
  variants remained undecided. This small sample is not a general accuracy estimate.
  Accurate Vision mode still has the separately documented host backend failure;
  only fast mode is used. No real card image or recognized text was added to Git.
- Collection processing starts only after capture close/exit, in an isolated
  exporter. Malformed progress is rejected; cancellation preserves pending pages
  and cannot trigger a replay. Terminating an exporter after confirmed capture
  closure does not invent a scanner-release failure. ICA processing checks a
  thread-safe cancellation flag before publication; manual recovery runs off the UI.
- The native profile panel was opened in a separate preview using synthetic holder
  dimensions, with no capture logic or real app settings access. Layout, visible
  controls and missing-height validation were inspected; the preview was closed.

**Still required on the real ES-C320W/driver 6.7.84:** derive and confirm ICA and
direct-feeding duplex mappings independently with driver autorotation off, including
a 90-degree case and swapped card faces. No hardware mapping has been fabricated;
without one the app explicitly uses fixed fallback. Also verify the entire outer
holder margins, centering and deskew interaction for fixed dimensions. Width with
automatic height remains unavailable until its own driver test passes. These gates
must not be counted as completed by the software tests or synthetic pair algebra.

Whole-branch review identified four Important issues, all addressed in one
regression-backed fix pass:

1. Export preparation, publication and final cleanup now share the parent-liveness
   predicate. Tests simulate parent loss during final export and finalization:
   no new publication after loss, and originals/receipts remain recoverable.
2. Real work checkpoints cover hashing, PDF page writing/validation, chunked JPG
   copies and finalization. The exporter has a 140-second inactivity window rather
   than a 20-second whole-tail deadline. Tests keep a healthy tail alive beyond 20s,
   extend it on a valid checkpoint, then demonstrate bounded cancellation on a stall.
3. The tested shutdown policy preserves explicit save-and-quit intent beyond 30s
   while supervised work continues, and completes on worker exit or a real failure.
   Ordinary pause/quit retains its 6-second bound.
4. New profiles require explicit disabled readback for competing driver rotation
   and fixed-area cropping. Both missing and mistyped rotation features were shown
   to authorize transport with the guard removed, and reject it with the guard active.

No Critical finding was identified. One Minor remains deferred: comprehensive
tagged-ICC color fidelity and non-normal EXIF/mirroring fixtures. The present normal
scanner-path marker/DPI tests do not establish those general metadata guarantees.
Review did not certify arbitrary imported/non-300dpi images, exhaustive power-loss
or publication-instruction fault injection, hostile same-user filesystem races,
a complete historical installed pending-job migration, every UI localization or
assistive-technology flow, or actual hung-Vision cancellation latency/large-job
throughput. Those broader guarantees are not claimed by this beta. Installation,
new release distribution and physical acceptance remain separate from this local
implementation check.

### Orientation — physical acceptance in progress, 2026-10-28

Build16 was installed locally with verified application/data backups. With Epson
driver rotation disabled and both fixed output rotations at zero, three physical
duplex scans produced six valid300dpi JPGs: portrait, a clockwise quarter-turn,
and portrait with the card faces exchanged. Each returned to ready/listening with
an empty Pending directory. Visual inspection and reference-image correlation
established the ICA relationship `back = -front (mod360)`: the quarter-turn
required corrections270°/90°, while both portrait cases required0°/0°.
This does not establish the separate direct-feeding relationship.

The new card also exposed a limitation in the original raw fast OCR score:
upside-down noise could score as highly as real words, including an incorrect
raw maximum on the physical quarter-turn. The conservative decision correctly
declined those cases. Enabling Vision's own language correction, rather than
lowering the decision gates or adding a spell-checking service, corrected the
sample. The existing production-analyzer regression failed with seven issues
before the change and passed afterward. The expanded private matrix now covers
five front inputs from three distinct cards (including actual swapped-face and
quarter-turn captures), in four digital rotations each; all20 decisions match
the expected correction. Four back-only variants remain undecided. The complete
98-test native suite and callback/geometry harness pass. Existing private spike
originals retain their recorded hashes and modification times.

Build17 contains this small OCR correction and is installed with another verified
app/data backup. The measured ICA mapping and macOS automatic orientation are
enabled in the private calibration profile. Automatic physical output, the
remaining direct-feeding geometry and fixed card/holder outside dimensions are
still under acceptance. The development candidate remains unpublished; these
results are a small controlled sample, not a general orientation accuracy claim.

Two subsequent physical ICA scans with automatic processing enabled passed:
an upside-down card, then a quarter-turn with the card faces exchanged. Both
published two visibly upright JPGs without processing notices and returned to
ready/listening with Pending empty. The second case changed the raw landscape
dimensions1045×740/1040×741 to portrait740×1045/741×1040, demonstrating actual
pixel rotation on both scanner channels. The first case used a different printed
card from the raw calibration captures, broadening the physical sample. Receipt
digests match all four final files. The macOS login item was also retargeted from
the older user-local copy to the installed application in `/Applications`; both
System Settings selection and enabled/allowed record readback were verified.
An actual logout/login was not performed during scanner acceptance.

The first physical63×88mm attempt exposed an ICA limitation: the driver echoed
the custom `scanArea`, but delivered the A5 preset1748×2480px. Its original rear
also showed a tilted/clipped leading edge with deskew enabled and autocrop off.
This attempt is a failed fixed-area acceptance, despite successful file saving.

Build18 intentionally changes ICA framing: select the smallest containing paper
preset, then frame its centered/leading-edge physical region before OCR/rotation.
There is no stretching or content-edge search. Fixed profiles require disabled
crop, deskew and vendor rotation; legacy/automatic-area deskew preferences remain.
Direct feeding still requires matching actual native dimensions. Fixed-area
Epson-rotation profiles remain decodable but cannot start a new capture. Older
fixed raw/processed jobs without verified capture/processing revisions remain
readable and retained, and cannot authorize publication or original deletion.

103 native tests pass, including the private orientation matrix and native harness.
Tests cover actual crop pixels before OCR/rotation, exact output dimensions,
repeat export without reprocessing, undersized capture retention, rejected
oversized direct-feeding frames, old inactive-profile/settings/job readability,
and failed export/cleanup of legacy fixed captures and stale oversized copies.
Each new defect was reproduced before its guard was implemented. Scoped
independent review identified the decoder and stale-processing reuse problems;
both were resolved with focused regressions, with no remaining Critical or
Important finding. That review did not certify physical framing or rerun tests.

Build18 builds and verifies, and is installed locally with verified app/data
backup. The card profile remains active at63×88mm; an inactive77×102mm holder
profile uses the user's measured outside size. The actual corrected fixed-frame
scan and holder mechanical suitability/border retention remain pending. No new
scan after this installation is counted as accepted until its images are checked.

The corrected physical ICA63×88mm scan delivered two744×1039px JPGs from the
selected A6 capture1240×1748px. Both capture/processing revision markers are1,
receipt digests match and there are no orientation notices. Both sides are
visibly upright; the rear outside edge is tight against the exact-size boundary,
so full-border retention is not claimed for that template. A65×90mm area with
reserve and duplex PDF is the next acceptance case. A thick rigid holder was
not fed: its reported dimensions/thickness are outside the confirmed
[Epson ISO ID-1 plastic-card specification](https://download4.epson.biz/sec_pubs/es-c320w/useg/en/GUID-A2F939AF-072A-4C13-9BE1-5E6AAD23B6BF.htm).

The subsequent ICA65×90mm duplex PDF has two pages,184.32×255.12pt from
768×1063px at300dpi (physical dimensions rounded to whole pixels). Poppler read
and300dpi rendering of both pages succeeded, and the receipt digest matches the
913,064-byte final file. Both sides stand upright with no processing notices.
The front is complete; the rear outside edge remains tight, so this is format
and orientation acceptance, not a general whole-border guarantee. The app
returned to ready/listening with Pending empty. Direct-feeding calibration is
now prepared separately with automatic area and fixed0°/0° output; no direct
mapping is enabled until actual geometry is measured.

Direct feeding was then measured independently with native rotation disabled:
normal portrait required0°/0°, and the clockwise quarter-turn required270°/90°.
Visual inspection, local OCR and a reference-back comparison agree on
`back = -front (mod360)`. Four staged originals were privately snapshotted and
hash-verified before physical Stop. Stop produced one1,365,431-byte four-page PDF
with a matching receipt and returned to ready/listening with Pending empty.
The readable face remained on channelA in these captures; physical swapped-face
acceptance on this path is still a separate final case, despite the insertion
instruction. Do not count it as demonstrated from the user's description alone.

Build19 includes both measured ES-C320W/driver6.7.84 mappings in newly created
profiles. An uncalibrated legacy/explicitly missing mapping still falls back.
The new-profile consumer regression failed before the change;104 native tests
now pass, including the private orientation matrix. Both native helpers already
restrict USB product400 and driver6.7.84, so these defaults do not extend support
to another model or driver. Build19 is installed with another verified app/data
backup; the final continuous fixed-frame test uses69×94mm with more reserve,
local automatic orientation and physical Stop. That final image result remains
pending and is not established by the software tests.

**Final local acceptance, build19:** a physical lower-edge-first card with its
blue back facing the user produced two815×1110px native fixed-area originals and
two identically sized processed pages. After physical Stop, the912,244-byte PDF
has two195.6×266.4pt pages (69×94mm at300dpi with whole-pixel rounding). Both
pages rendered successfully at300dpi and were visually inspected: blue back on
page1, readable printed face on page2, both upright. Thus the readable face was
actually on channelB in this final direct-feeding case. Both original-to-output
digests changed, there are no processing notices, capture/processing revisions
are1, the final PDF digest matches its receipt, and the app returned to
ready/listening with Pending empty. The fixed native area was actually delivered,
not just echoed by a setter. This accepts the demonstrated duplex orientation,
dimensions, PDF export and physical Stop workflow on the tested device.

The leading-edge boundary may remain flush with the card; these samples do not
establish arbitrary overscan or guaranteed entire outer borders for all insertions.
No thick-holder feed was performed, automatic height remains unavailable, and
the previously observed darker direct-feeding color remains outside this change.
This pass did not repeat a jam, forced mid-image stop, inactivity timeout,
sleep/wake or unplug test; earlier evidence and software guards remain separate.

Final installed bytes match the verified build19 manifest.104 native,26 Node
and42 Python tests pass (172 total), plus the native callback/geometry harness.
The package tests also exercise actual DMG/ZIP behavior. New source/runtime and
private card evidence stay separate; no real scan or OCR text entered Git.
The normal destination and PDF-per-card/duplex preferences were restored through
the UI, automatic feeding is off by default, and its stored timeout is again120s.
The active profile uses69×94mm/local automatic orientation; a measured77×102mm
holder profile is retained inactive. The owned temporary calibration profile was
removed with backups retained. The login item readback after build19 remains
enabled/allowed at the `/Applications` app path; no real logout/login was needed.
This completes the authorized local installation and the demonstrated scanner
tests, with the explicit media/image-quality limits above. Publication remains
separate from this local acceptance.
Finally the status window was closed. A process readback confirmed the installed
main application and its parent-bound button receiver still running in the
background; the app was left ready for the physical scan button.

### Transparent-holder correction, build20 — 2026-10-29, local only

The original physical Toploader attempt failed acceptance: the fixed acquisition
area discarded transparent trailing material, and a text-poor Energy face did
not meet the OCR confidence gates. Native overscan was independently unsuitable:
a narrow area corrupted rows and a full-width area repeated trailing pixels.
Those configurations are not used by the new transparent profile option.

An Epson UI comparison and independent native regular scans demonstrated full
holder edges with automatic cropping, laminated mode and positive crop margin.
The production helper reuses the supervised AF path with the supported0.20in
margin and full sensor area; one-card mode finishes after its first batch.
That exact AF configuration still requires the physical build20 button test.
Fixed dimensions now describe a centered output canvas without scaling; only
its known capture margin may be removed. A protected-content mismatch retains
originals instead of exporting. Revision2 stamps distinguish this capture and
processing from historical fixed frames.

Optional upright references store a bounded, securely archived Vision revision1
feature print. A match requires distance<=12 and at least20% separation between
rotations. Either physical face can determine its paired rotation; reliable OCR
conflicts remain visible. A same-native-path reference passed52 private sample
variants including both complete holder captures at four rotations; unrelated
card fronts were rejected. Cross-path color differences can leave a valid card
uncertain, so users should select a reference from their own capture path.
Perspective normalization and grayscale experiments did not improve this result
and are not included. Private scans, feature prints and sample matrices are not
part of the repository.

Local software checks:122 native tests plus the Objective-C callback/configuration
harness,26 Node tests and42 Python/package tests passed. Build20 compiles and is
ad-hoc signed, still not notarized. Tests cover complete one-batch JPG/PDF handoff,
Stop/stall bounds, centered pixel placement without stretch, too-small frames,
legacy framing rejection, reference corruption/size limits, either duplex channel,
conflicts and cancellation before publication. Actual holder border completeness,
sharpness, orientation and repeated physical Stop behavior remain pending below.

The independent final review found one orientation conflict issue: a combined
uncertain result or a failure on the other face could hide a confident per-face
OCR result. Both channel orders now retain successful evidence and compare each
reference-derived pair against it. The new decision and full-storage/export
regressions reproduced6 failures before the correction; all122 native tests
pass afterward. No Critical or Minor findings remained. This is a local test
installation, not a publication or broad hardware acceptance.
