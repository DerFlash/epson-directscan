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
| GitHub-hosted CI | [Check workflow](https://github.com/DerFlash/epson-scansmart-autosave/actions/workflows/check.yml) runs on pushes and pull requests |
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
