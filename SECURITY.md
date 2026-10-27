# Security and privacy

This source beta operates locally. It makes no network requests and includes no
telemetry, credentials, scan samples or Epson software. It reads ScanSmart window
metadata, stores a selected destination and transaction state, and checks expected
JPEG files using local ImageIO decoding, complete source/frame status, positive
dimensions and stable sizes. Image pixels are decoded in local memory for this
check. It does not upload scan contents.

Settings, state and bounded logs are stored under
`~/Library/Application Support/ScanSmart AutoSave/` with private permissions.
Event logs use codes and counts. The separate bounded timing log contains only
timestamps, known codes/action types and numeric durations/intervals; it never
contains window text, destination paths or image data. Treat state/configuration as private: they may contain
folder names or expected file paths. Inspect and redact any diagnostic material
before sharing; never attach actual scans or private customer information.

The app needs its own Accessibility and Automation permission. Native Quartz
clicks are guarded by a fresh foreground process check. A small non-atomic race
between that check and the click remains: avoid changing foreground apps while
an enabled export is being processed. Uncertain outcomes pause; do not retry
blindly. Inspect the output and finish or cancel pending ScanSmart work manually.

For a suspected vulnerability, contact the repository maintainer privately through
an available private repository contact channel. If none is available, open only a
minimal issue requesting a private channel; do not publish sensitive reproduction
data. No guaranteed response time or security support period is offered for beta.


## Native DirectScan candidate

The separate native candidate uses ImageCaptureCore for scans and an isolated
helper for the installed Epson Scanner.framework internal button API, without
Accessibility or System Events. The helper refuses any driver version except
the checked 6.7.84 and verifies method signatures before calling it. No Epson
binary is redistributed. Each physical button must be followed by confirmed
helper close and process exit before the separate ICA scan process starts; the
next receiver starts only after confirmed scan completion, close and exit. Its first connection and recovery share an explicit takeover
confirmation. It temporarily unloads the current user's two known Epson launch
agents while listening; no vendor files or persistent disable settings change.
The original loaded labels are recorded privately and restored after confirmed
scanner release. On an unconfirmed close or abrupt process exit, the memo stays
for restoration on the next app launch (or normal agents return at next login).
Each helper independently holds the shared scanner.lock OS lease through hardware
open and close. Startup restoration and a new connection also check it, so a
surviving/blocked old helper keeps recovery blocked after its parent exits. Do not
delete the memo or lock file to suppress an error. The candidate never alters the
scanner's global auto-launch application assignment. The legacy ICA callback/KVO
route did not deliver events and has been removed from the scan worker. Three real
button scans passed through the Epson-specific helper; other driver versions,
models and extended recovery/login behavior remain unverified. A short startup
drain rejects early button events; busy or late events cannot queue a scan.

JPG handoff uses private per-job staging, complete eager ImageIO decoding with
per-frame status, and atomic exclusive rename into the chosen destination.
Failures preserve staging and never retry the physical scan. Native diagnostics
exclude images, OCR, device serials and arbitrary window contents. Configuration
and retained job metadata may contain the user's selected local path.
