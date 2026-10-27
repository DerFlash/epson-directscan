# Changelog

## Unreleased

- License the project under PolyForm Strict 1.0.0; modifications and redistribution
  require separate permission. Commercial use outside
  its express permissions requires separate prior written permission from
  Björn Teichmann; no commercial license or software purchase is offered for sale.
- Include the license and licensing/contact notice in native and legacy app
  bundles and native DMGs. Refuse packages with missing or stale bundled notices.

## 0.3.0-beta.2 — 2026-10-27

- Rename the repository to `DerFlash/epson-directscan`, retaining issues,
  releases, history and old URL redirects. Update active canonical links.
- Provide a ready-built Apple-Silicon app as DMG and ZIP, plus source/checksums.
  The DMG includes an Applications link and installation/upgrade notes, runs no
  privileged installer and changes no security/login settings.
- Clearly label this beta ad-hoc signed and not notarized, with the macOS
  first-open confirmation described. No Epson binaries or private data bundled.
- Validate package input identity, arm64 slices, signatures, copied bytes and
  executable/access permissions; reject existing output. Add real DMG/ZIP tests.
- Promote metadata to build 15; capture/storage/helper code remains the tested
  build 14 logic. Existing installed copies and user data are left untouched.
- 138 local software tests (70 Swift, 26 Node, 42 Python) including 4 package tests;
  source/runtime and image-quality limits remain as documented for beta1.

## 0.3.0-beta.1 — 2026-10-27

First public native DirectScan source beta, promoting the tested build 14 logic.

- Replace the ScanSmart frontend with the separate native menu-bar app: choose
  a destination, press the physical Epson Start button and save directly.
- Add duplex JPGs, a PDF per card and continuous automatic feeding into one PDF,
  with physical/app Stop and configurable idle timeout. Keep 300 dpi color and
  switchable Epson crop, deskew and text-orientation processing.
- Correct empty Stop handling; bound active capture without a complete page to
  15 seconds before requesting cancellation. Preserve real jam/device errors,
  incomplete data and confirmed-close/exit barriers; never replay capture.
- Explain scanner faults and reconnecting after USB removal. Preserve existing
  login registration and backup an installed app before replacement.
- Publish native-first guides, recovery/security notes and acceptance limits.
  Keep the older UI helper separately documented. Add native checks to CI.
- 134 local software tests plus the callback contract harness and ES-C320W USB
  device checks passed; see `docs/VALIDATION.md`. Driver compatibility remains
  limited to 6.7.84. Card orientation and darker AFM output remain open (#1/#2);
  automatic USB reconnection, long series and forced mid-image hardware Stop
  are not accepted features. Source only: no Epson binaries or private scans.

The following unreleased headings are the historical development records now
included in this native release; the legacy timing helper remains a separate
code snapshot.

## Unreleased — native duplex/PDF beta (local only)

- Add duplex JPGs with shared card numbers and front/back suffixes, or one PDF
  per card. Keep existing 300 dpi and driver-correction controls.
- Add true Epson automatic feeding after one physical Start: collect pages until
  physical/app Stop or 30/60/120/300 seconds of inactivity; optional unlimited.
- Preserve complete pages across interruptions, flag incomplete final duplex
  cards, verify PDF geometry and journal exclusive exports without overwriting.
- Migrate settings with an exact private backup. Preserve the app path, bundle
  identifier and existing login registration. No public release is part of this work.
- Verify duplex JPG, per-card PDF, reinsertion without Start, physical Stop,
  automatic idle completion and retained-page recovery on the local ES-C320W.
  55 Swift tests, the mandatory-callback harness and all64 legacy tests pass.
- Epson orientation detection needs readable text; colorful cards may remain
  inverted, and the AFM output may be darker than ordinary scans. Local beta
  hardware acceptance and remaining limits are recorded in docs/VALIDATION.md.

## Unreleased — native DirectScan beta (local only)

- Add a separate Swift menu-bar app with destination selection, three driver
  correction switches, private staging/recovery and guarded JPG handoff.
- Receive the physical button through an isolated helper using the installed
  Epson Scanner.framework. Restrict the internal API to checked driver 6.7.84;
  require confirmed close and process exit before an isolated ICA scan starts.
- Reject incomplete JPEG frames, duplicate/early/late triggers and invalid process
  messages. Deliver live helper events immediately. Never replay uncertain scans.
- Preserve previous local builds, share connection/recovery consent, and return
  Epson services only after confirmed release. Leave login items unchanged.
- Hold a shared OS ownership lock in both helpers so startup recovery cannot race
  a surviving helper. Keep service restoration blocked until the lock is free.
- 32 native tests and three real ES-C320W USB button scans passed, including a changed
  destination and automatic rearming. Broader reliability remains unverified;
  this native development build is not publicly released.

## Unreleased — timing controls

- Add configurable polling intervals of 100–2000 ms (default 250 ms), with native
  menu controls and migration of existing settings. Interval-only changes keep
  in-flight action reservations intact.
- Add local per-poll timing and a human-readable summary, with a bounded private
  log and no paths/window text. Diagnostic failures cannot reset a scan.
- Skip the separate destination-setting action when the current folder is already
  exactly correct; keep the fresh Save guard and collision checks.
- Avoid unused remote value/name reads on structural, image and preview elements;
  keep all data consumed by the supported roles and both guarded snapshots.
- Preserve all existing dispatch, collision, file verification and timeout guards.
  A paired single-card check measured 14.5 → 11.9 s for the save workflow;
  longer series and hardware scan/feed time are outside that comparison.

## 0.1.0-beta.2 — 2026-10-26

- Fix resource loading and JSON null handling in the compiled AppleScriptObjC app.
- Preserve the exact `actionId` key across the native bridge so reserved actions
  can be dispatched and acknowledged.
- Ignore only the exact macOS window-sharing indicator; real dialogs still block
  automation. Retry transient read-only UI observations for at most 10 seconds,
  without repeating a reserved or uncertain action. Keep actual permission errors
  distinct and show their native error number.
- Wait for export fields to finish loading, read the two export combo boxes
  without preview-field interference, and support the single-image Save view
  whose page counter is hidden. Confirm an already-correct destination without
  rewriting it.
- Require an unnumbered .jpg/.jpeg suffix before treating a counterless view as
  one image. A partial multi-image view cannot bypass collision checks by hiding
  its page count. Add regression coverage for this case, the compiled native
  bridge and a complete single-image export cycle.
- Record one successful physical single-card button scan on ES-C320W USB,
  German ScanSmart 3.7.22 and macOS 27.0.1. Longer sequences and the remaining
  hardware acceptance cases are still unverified.

## 0.1.0-beta.1

Initial source beta: standalone stay-open helper, destination picker, enable/pause,
dry run, status and reset; strict German ScanSmart JPG flow; persisted action
reservations and file verification. Local signed build and explicit installation.
New beta hardware acceptance remains pending. Predecessor observations do not
certify this release.
