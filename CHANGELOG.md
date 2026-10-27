# Changelog

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
