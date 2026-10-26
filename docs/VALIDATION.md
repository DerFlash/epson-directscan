# Timing-controls development validation

This branch adds interval controls and local measurements after Beta 2. Current
input-free tests: 24 Node + 37 Python pass. The full compiled poll orchestration
is exercised with substituted GUI/runtime I/O. Real physical timing acceptance
for this development build is pending; no throughput improvement is claimed.

An input-free stay-open macOS applet requested 250 ms and observed 262.0,
262.3 and 258.0 ms between idle callbacks. The 1000 ms control observed 1050.8,
1051.3 and 1050.4 ms. This verifies subsecond scheduling on this Mac; it does not
measure ScanSmart or prove a full scan's speed. The internal resource bridge
averaged 19.2 ms over eight getSettings requests with isolated test storage.

The first physical timing-controls test exported exactly one readable JPG without
Mac clicks, preserved the existing 15 JPGs and returned to ready. From the first
action poll through saved it took 14.465 seconds. Measurements identified about
2.0 seconds per Save-view capture, plus the fresh capture inside an action.
The next optimization avoids value/name AX reads for roles whose text is never
consumed; it keeps both snapshots and all dispatch guards. Its physical timing
comparison is recorded separately after local installation.

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
