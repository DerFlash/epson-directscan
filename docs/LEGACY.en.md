# Legacy ScanSmart AutoSave helper

> This document covers the older UI-automation helper included in the source tree.
> For the native v0.3.0-beta.1 menu-bar app, use the [main README](../README.md)
> and [German native guide](NATIVE.de.md). Do not run both apps together.

GitHub project: [DerFlash/epson-directscan](https://github.com/DerFlash/epson-directscan).

**Source beta; one complete scanner-button export has passed.** The corrected
implementation saved one card as a readable JPG without Mac clicks on 2026-10-25,
using German Epson ScanSmart 3.7.22, macOS 27.0.1 and ES-C320W over USB.
Longer scan sequences, repeated cycles, destination changes during real scans and
restart behavior still need hardware acceptance. Other languages, scanner models,
layouts, formats and macOS versions are unverified. Unsupported views pause automation.
This independent project includes no Epson software and does not require Codex.

It completes the two German ScanSmart save steps for JPG exports after a
scanner-button scan. Resolution, sides and filename prefix remain ScanSmart
settings. It never activates ScanSmart; ScanSmart must already be foreground.

[Deutsche Anleitung](README.de.md) · [Design](design.md) ·
[Security and privacy](../SECURITY.md) · [Validation](VALIDATION.md) · [Changes](../CHANGELOG.md)

## Build and install

Use macOS with `osacompile`, `codesign` and the system scripting frameworks.
No third-party app runtime is needed. Developer tests use Node.js and Python 3.
From the source directory (quoted paths and spaces are supported):

```sh
./scripts/test.sh
./scripts/build.sh
./scripts/install.sh
```

Build produces `build/ScanSmart AutoSave Beta.app`, bundles all three JavaScript
resources, sets stable metadata, then ad-hoc signs and verifies it. It does not
launch, install, change permissions or configure autostart. Existing build output
requires `./scripts/build.sh --replace`. An explicit signing identity can be used
with `./scripts/build.sh --sign 'YOUR SIGNING IDENTITY'`; this does not notarize it.
The bundle ID is `org.scansmart.autosave.beta`; marketing version is `0.1.0`,
build `3`, beta version `0.1.0-beta.3-dev`.

Install defaults to `~/Applications`. It refuses an existing app unless you pass
`./scripts/install.sh --replace`; quit the installed helper and any predecessor
first. An alternative directory must be absolute:
`./scripts/install.sh --destination '/absolute/path/Applications'`.
Installation never launches the app or adds a login item. Never run two helpers
at once, including an older script/helper.

The local app is ad-hoc signed, not notarized. This is a source release; a broadly
downloadable binary would require stable Developer ID signing and notarization.
Do not treat a build command or passing tests as hardware acceptance.

## First use and permissions

1. Open the installed app manually. It starts disabled. Click its Dock icon to
   open the controls: destination folder, enable/pause, status, dry run and reset.
2. Choose a writable destination. Grant **this app** access in macOS System
   Settings → Privacy & Security → Accessibility (on newer German macOS versions:
   “Gerätesteuerung und Datenzugriff”). When asked, also allow this app
   to control System Events under Automation. Granting permission to Terminal or
   Codex does not grant it to the standalone app.
3. Finish or cancel existing pending ScanSmart exports manually. Enable dry run
   first, then enable the helper. Let it observe ScanSmart outside a pending
   Choose/Save page before starting a new scan: use ScanSmart’s normal start screen
   before scanning. “Aktion wählen” is the pending Choose page, not an idle screen.
   Keep ScanSmart foreground.
4. Check planned actions in dry run. Manually complete or cancel that sample
   export. Disable dry run after checking the destination; this rearms the helper
   and requires another idle observation. It cannot immediately auto-save the same
   pending sample. Start a fresh non-sensitive test scan and verify its files.

Ad-hoc rebuilds can change the permission identity despite a stable bundle ID.
After replacement, quit the app, remove its stale Accessibility entry and add the
new installed app again if permission fails; review its Automation entry and
respond to the new prompt. No script changes permissions for you. Do not grant
permissions to unfamiliar copies.

## Polling interval and local timing

Open the app controls and choose **Prüfintervall wählen**. Available intervals are
100, 250 (default), 500, 1000 and 2000 ms. The interval is the requested gap after
a poll; macOS scheduling, UI reads and Epson processing add their own time.
Disabled or paused mode uses two seconds. Changing only the interval preserves a
pending transaction and does not require idle rearming. The 10/30/120-second
error limits and all Save guards remain unchanged.

**Zeitmessung anzeigen** shows recent active steps, including window-read,
action and total processing time. Processing excludes the scheduling gap; the
action measurement includes its fresh UI recheck and dispatch acknowledgment.
The app keeps at most 128 sanitized records in private `timings.json`, with
timestamps, codes and numeric durations. Idle polling does not overwrite the
last scan's measurements. No window text, paths or image content are recorded.
Local single-card checks measured 14.5 → 11.9 seconds after optimizing capture
reads, then 11.9 → 9.0 seconds after omitting the already-correct folder step.
All these runs used 250 ms polling. This
excludes hardware scan time and is not a series benchmark. See
[VALIDATION.md](VALIDATION.md).

## Configuration and recovery

Settings and transaction state live outside the signed app at
`~/Library/Application Support/ScanSmart AutoSave/`, alongside bounded logs.
Defaults: no destination, disabled, dry run off. Use the app controls instead of
editing internal files. Dry run reports plans without changing fields or clicking.
Enabling, restarting, resetting or changing destination requires a fresh idle
observation before actions can occur.

A click means dispatched, not saved. Completion requires the expected nonempty
JPEGs to pass local ImageIO decoding as complete single-frame images with positive
dimensions, stable file sizes across two observations and a closed Save page. Existing
target files, errors, ambiguous metadata, unsupported screens and timeouts pause
it. A downstream app moving files immediately may prevent verification and pause.

On pause, inspect the actual output directory and ScanSmart. Finish or cancel any
pending export manually; preserve files from an uncertain save. Then use Reset
and return ScanSmart to an idle screen before a new scan. The helper never
retries an uncertain Save automatically. Do not delete files just to bypass a
collision. Transition timeout is 30 seconds; export verification allows 120.

Native mouse events are necessary for Epson custom controls. A fresh foreground
bundle/PID check precedes each click, but a small check/click race remains. Avoid
switching apps during export. No keyboard shortcuts or general error-dialog
clicking are used.

## Troubleshooting, verification and removal

- No actions: check enabled state, destination, idle arming, foreground ScanSmart,
  own app permissions and German JPG view. Unknown dialogs must be handled manually.
- Permission failure after rebuild: refresh the installed app's permission entries
  as described above, then relaunch it manually.
- Pause after export: inspect files before Reset. Do not assume dispatch completed.
- Duplicate actions: quit every helper copy, including the predecessor.

Recovery codes shown in status:

| Code | Meaning and next step |
| --- | --- |
| `invalid_metadata`, `counter_overflow` | JPG filename, suffix or page count is ambiguous or out of range. Complete/cancel manually; check ScanSmart naming and JPG settings. |
| `target_exists` | At least one expected file already exists. Preserve it; choose a new filename/destination before a fresh scan. |
| `destination_readback`, `destination_rejected` | Destination change was not confirmed. Check the folder and finish/cancel manually. |
| `unsupported_view` | Unknown or blocked ScanSmart view. Handle the dialog manually; use the supported German layout. |
| `transition_timeout`, `export_timeout` | Screen transition or file confirmation timed out. Inspect actual files before resolving the pending export. |
| `permission_denied` | Review this app’s Accessibility/Automation permissions. |
| `ui_changed`, `dispatch_failed` | The window changed or dispatch could not be confirmed. Inspect ScanSmart and files; never retry blindly. |
| `adapter_error`, `bridge_error`, `unknown_action` | Internal interaction state is uncertain. Pause, inspect files and pending work, then restart/reset after resolving it. |
| `storage_error` | Private settings/state could not be read or saved. Quit; check folder access and preserve diagnostics before resetting local data. |
| `invalid_destination` | Select an existing writable destination through the app. |
| `invalid_settings`, `unknown_request` | Invalid internal request/settings. Restart the current build; report repeated errors with redacted diagnostics. |

After fixing a paused condition, use Reset and let the helper observe the normal
start screen before a new scan. Reset does not prove that an earlier save failed.

`./scripts/test.sh` runs Node core tests and Python tests without GUI permissions.
CI runs core tests on Linux and tests plus app compilation/signature verification
on macOS. Automated checks cannot prove Epson GUI behavior, real permissions,
scanner-button operation or hardware save completion. One physical single-card
cycle has passed; the remaining hardware acceptance checks are listed in
[VALIDATION.md](VALIDATION.md).

To remove: quit the app, delete its installed `.app`, and remove its permission
entries in System Settings if desired. To reset all local state, separately remove
`~/Library/Application Support/ScanSmart AutoSave/` only after resolving any pending
export and preserving needed diagnostics. Destination scans are separate and are
not removed by uninstalling. No autostart entry is created.

No network access, telemetry or image upload. Private state may contain paths;
redact diagnostics before sharing. See [SECURITY.md](../SECURITY.md).
Source-available under the [PolyForm Noncommercial License 1.0.0](../LICENSE);
see [licensing and commercial-use enquiries](../LICENSING.md).
