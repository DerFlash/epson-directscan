# Security and privacy

The main v0.3 release is the native DirectScan app described below. The first
section documents the separately retained legacy ScanSmart UI helper; its
Accessibility/Automation permissions do not apply to DirectScan. No Epson
binaries, real scans or private settings are included in release archives.

## Legacy ScanSmart helper

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


## Native DirectScan v0.3 source beta

The separate native app uses ImageCaptureCore for scans and an isolated
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
delete the memo or lock file to suppress an error. The native app never alters the
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


The native duplex/PDF extension keeps the same device ownership and close/exit
barriers. Its automatic-feeding helper additionally uses Scanner.framework AFM
and ImageProcessor/Esaod for orientation, guarded to installed version6.7.84.
No vendor binaries, OCR output or scanned images are included in source control.
A user-authorized physical Start opens an insertion session; subsequent insertions
only scan within that active session. Physical Stop or the configured idle timer
ends it; active transfers are excluded from inactivity. Session error/parent death
retains pages and never replays a scan. SIGUSR1 requests graceful finish separately
from abort/termination. After installing its handlers, the worker reports Ready
and waits for a separate parent SIGUSR2 before arming the feeder; queued finish
intent closes it without starting capture. Original JPGs remain private until verified export; receipts
identify the renamed inode and digest, allowing crash reconciliation without
accepting a colliding replacement. Diagnostic logs contain no recognized text.

Export grouping is persisted before publication, including explicit recovery as a
collection PDF from an ordinary job. A retry reconciles the same transaction and
cannot silently switch format. A successfully exported collection with an
incomplete final duplex sheet keeps its source job and manifest privately in
Recovery for inspection instead of deleting the originals.
