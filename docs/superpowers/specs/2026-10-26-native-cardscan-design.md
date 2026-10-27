# Native Epson card scanning app

User request: a small macOS menu-bar app, configurable output folder, the tested
driver image corrections, and continued physical Epson Scan-button initiation.
Build and local testing are authorized. New public publication is not requested.
The user approved this document and chose the existing project folder on a new
branch (feat/native-directscan). Implement locally in this session.

## Approach and evidence

Use Swift/AppKit and ImageCaptureCore with the installed Epson ICA driver.
Two real USB ES-C320W scans succeeded independently of ScanSmart. The second
enabled VF_AUTOCROP=1, VF_DESKEW=true and VF_AUTOROTATE=true, producing a readable
745x1040 JPEG at 300 dpi in 3.994 seconds from requestScan to file receipt.
The amount of rotation/skew correction was not independently measured.

A menu-bar shell around the old AppleScript helper would retain its UI delays
and foreground/Accessibility requirements, contrary to the requested direct app.
Replacing the Epson driver or building a separate image-processing pipeline is
unnecessary for these tested features. Native direct scanning is the selected
approach implied by the user's request after the two successful direct tests.

## Small first version

Proposed app name: Epson DirectScan Beta; a separate bundle ID and settings store.
Add a native/ Swift package to the existing repository. Retain the legacy helper
as a fallback and document the two paths clearly. Build a local ad-hoc signed
app, install in ~/Applications, and run a hardware acceptance test. No external
dependencies, cloud, telemetry, network scanning or image upload in this version.
Target macOS 13+, initially verified only on the current Mac/macOS and USB model.

Menu: readable scanner/scan/error status; pause/resume; output-folder picker and
open folder; three correction switches (all on by default); last saved result;
reconnect/recover; quit. Default output on this Mac: Documents/Scans. New installs
must select a writable folder. Format fixed to JPG, 300 dpi, RGB, single sided.
Use unique timestamp/UUID filenames. Changes apply to the next scan and controls
that could mutate an active job are disabled until it completes. The app has no
Dock icon or persistent main window. Foreground activity must not affect scanning.

Run while app is open; an optional explicit “start at login” control is allowed
if supported reliably by the signed local app. It is off by default; do not
silently change existing login items. Disable/quit the old helper during direct
app testing so only one scanning workflow is active. Preserve its files/settings.

## Physical button and lifecycle

Must prove device-button event delivery on the real ES-C320W. Begin with a
bounded event-only probe holding an ICA session; do not scan merely on startup,
paper insertion, reconnect, or opening settings. Test the documented device
button callback and status notifications. Only the scan-button event while ready
may initiate a job. Ignore repeated events while busy; never queue surprise scans.
Do not silently fall back to GUI automation or replace the hardware button with
a menu command. If Epson's background monitor intercepts the button, investigate
and report the required reversible configuration before altering its assignment.
The button route is an explicit feasibility gate; do not claim it works untested.

Listening may require an exclusive ICA session. Pause/quit closes it so other
scanner apps can use the device. Show disconnected/occupied/driver-error states.
Reconnect attempts must be bounded/backed off and never trigger a scan. Sleep,
unplugging, reconnect and quitting while busy must not duplicate scans or discard
an uncertain output. Preserve scans on errors and require deliberate recovery
after any uncertain scan result. Device enumeration must not select a different
model/transport or change global scanner/network settings.

## Saving and errors

Scan to an app-owned unique local staging directory. Validate each delivered file
as a complete decodable nonempty JPEG with positive dimensions before publishing
into the selected destination. Publish without overwriting; handle errors without
automatic scan retries. Publish pages as they arrive so a downstream consumer can
move them after handoff. A scan may contain all loaded feeder pages; duplicate
button events cannot start another concurrent job. Count only successful exports.
Retain unexported files for recovery when destination becomes unwritable, scan
fails, times out, device disappears or the app restarts during a job. Never label
a failed/partial export as a complete job; explain where to recover retained files.
Settings are atomic/private outside the signed app. Logs are bounded, use codes
and timings, and exclude image contents, OCR and device serial numbers.

Unavailable requested corrections or rejected readback must show an error before
scan rather than silently saving uncorrected results. Read/set functional units
only after deviceDidBecomeReady, as established by the successful prototype.

## Verification

Meaningful tests cover button/busy/state transitions, failures/disconnects,
configuration snapshots, collision-safe export and recovery, and image validation.
Verify native build/signature and legacy tests. Hardware acceptance: device button
to JPG with the three corrections, repeated second scan without Mac interaction,
destination selection, and session release via pause. Investigate only failures
or new changes; no repeated broad test runs without a reason.

## Builder choices and boundaries

Builder may choose small internal types, file layout, status symbols and German
wording. Keep implementation and tests proportionate; no large scanning framework,
OCR, card identification, PDF workflow, auto-update, distribution notarization or
public release. Button feasibility and user-facing behavior must remain explicit.
