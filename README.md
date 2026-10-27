# Epson DirectScan — v0.3.0-beta.1

A native macOS menu-bar app for the **Epson ES-C320W over USB**. Press the scanner's
Start button and save directly to a chosen folder, without the ScanSmart frontend
or further Save clicks. This independent project includes no Epson software.

[Deutsche Anleitung](docs/NATIVE.de.md) · [Releases](https://github.com/DerFlash/epson-scansmart-autosave/releases) · [Validation](docs/VALIDATION.md) · [Changes](CHANGELOG.md) · [Security](SECURITY.md)

## Features

- Menu-bar status, pause/reconnect and destination-folder selection.
- 300 dpi color; single-sided or duplex scans as separate JPGs or one PDF per card.
- Continuous automatic feeding: press Start once, then insert more cards without
  pressing Start again. Collect one PDF until physical/app Stop or a configurable
  inactivity period (30/60/120/300 seconds, or unlimited).
- Switchable driver crop, deskew and text-based orientation detection.
- A 15-second no-completed-page guard during active capture. Empty Stop completes
  with a clear notice; real device faults remain visible and retain data.
- Private staging, verified exclusive exports and explicit recovery. No uncertain
  scan is automatically replayed and existing output files are never replaced.
- No Accessibility or System Events permission for the native app. No image upload.

## Supported and tested setup

**Source beta**, tested on one Apple-Silicon Mac with macOS 27.0.1, ES-C320W USB
and Epson driver **6.7.84**. The internal Epson interface is version/signature
checked; other driver versions are refused. Other scanners and Wi-Fi are not
supported. macOS 13+ is the build target; other Macs/OS versions are unverified.

The source ZIP has no prebuilt notarized app, vendor binaries, real scans or
private settings. Install Epson's driver separately and build locally using
Apple's command-line tools. The locally tested toolchain is Swift 6.4/CLT;
native development tests need Swift Testing and Python 3. Legacy tests also use
Node.js. The installed native app needs none of those test runtimes.

## Build and install

From the extracted source directory:

```sh
./scripts/test-native.sh
./scripts/build-native.sh
./scripts/install-native.sh
```

This creates and ad-hoc signs `build/Epson DirectScan Beta.app`, then installs it
to `~/Applications/Epson DirectScan Beta.app`. Quit an installed copy before an
update and use `--replace` on the build/install scripts. The installer preserves
the previous app in a private ZIP backup. Bundle ID and build number remain
`org.scansmart.directscan.beta` / `14`; this release promotes the tested build14
logic from its development version to `0.3.0-beta.1`.

1. Quit ScanSmart, Event Manager and older AutoSave helpers. Connect the ES-C320W
   directly by USB and open **Epson DirectScan Beta**.
2. Choose an existing writable output folder and confirm temporary takeover of
   the two Epson button agents. They return after confirmed scanner release.
3. Wait for **Bereit**, insert one expendable test card in the straight paper
   path and press the scanner's Start button. Check the resulting files.
4. Close the status window to keep scanning from the menu bar. Add the app to
   macOS Login Items if desired; an existing entry at the same path is preserved.

See the [German guide](docs/NATIVE.de.md) for all settings, continuous feeding,
updates, permissions, fault recovery and removal. The app does not add autostart
or change the scanner's global launch-app assignment automatically.

## Beta limits and recovery

- Automatic rotation is not reliable for colorful cards or card backs
  ([issue #1](https://github.com/DerFlash/epson-scansmart-autosave/issues/1)).
- Continuous scans of the test card look darker than ordinary scans
  ([issue #2](https://github.com/DerFlash/epson-scansmart-autosave/issues/2)).
- A real paper jam requires physical clearance. After USB disconnect/power-off,
  close any Epson scan app and reconnect DirectScan explicitly. Automatic USB
  reconnection is not included. Empty Stop/pickup recovery is tracked in
  [issue #3](https://github.com/DerFlash/epson-scansmart-autosave/issues/3).
- Long series, sleep/wake, actual logout/login and forced mid-image cancellation
  have not been accepted on hardware. Do not treat this beta as general device
  or production certification.

On an error, inspect retained files before **Fehler zurücksetzen und neu
verbinden**. Never delete the private lock or service memo to bypass a failed
release. Use explicit PDF recovery for completed retained pages; no scan is
repeated by reconnecting. Settings, jobs and bounded numeric diagnostics stay
under `~/Library/Application Support/Epson DirectScan/`; redact private paths
before sharing diagnostics.

## Verification and older helper

The release has **134 local software tests** (70 Swift, 26 Node, 38 Python), plus
the compiled Epson callback contract harness. Device checks covered physical
Start, duplex JPG/PDF, continuous reinsertion, Stop and idle finish, empty Stop,
the pickup guard, retained-page recovery and a successful card scan after
clearing a real jam. Scope and remaining cases: [VALIDATION.md](docs/VALIDATION.md).
CI checks native core/helper contracts and compilation without Epson hardware;
the Epson orientation integration test requires the separately installed driver.

The older ScanSmart UI helper remains in `src/` with separate build/install
scripts. Its [English guide](docs/LEGACY.en.md) and [German guide](docs/README.de.md)
are retained for existing users. It has different permissions and workflow;
never run it alongside DirectScan.

MIT licensed. No affiliation with or endorsement by Epson.
