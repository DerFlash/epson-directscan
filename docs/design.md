# ScanSmart AutoSave 0.1 beta

Source beta for macOS. It completes the two save steps in German Epson ScanSmart for JPG exports after a scanner-button scan. It is independent of Codex and contains no Epson software. The app offers a destination-folder picker, enable/pause, status, dry run and reset through its Dock icon. Configuration lives outside the signed app. Resolution, sides and filename prefix remain ScanSmart settings.

## Safety and recovery

The app starts disabled. Enabling, resetting, restarting or changing destination arms it only after it has observed ScanSmart outside a pending Choose/Save page. Existing pending exports must be completed or cancelled manually. The app never brings ScanSmart to the foreground. Actions require the exact app, known German view, unique Save control, permitted window/sheet structure, JPEG suffix and valid metadata. It sets only a unique absolute-path field, verifies the readback, then saves. No keyboard shortcuts or broad error-dialog handling.

A persisted transaction reserves each action before dispatch. A click means dispatched, not saved. Save success requires the expected files to exist as nonempty JPEGs, have stable sizes across two observations, and the Save page to close. Existing expected files, errors, unsupported views and timeouts pause automation. It never automatically retries a Save after an uncertain outcome. Reset rearms after an idle screen. Fast downstream consumers may prevent verification; this pauses safely.

Native Quartz mouse events are necessary because Epson's custom controls ignore accessibility press actions. The app rechecks foreground bundle and PID immediately before posting. A small non-atomic check/click race remains, documented as a beta limitation. No network access, telemetry, image upload or embedded credentials. Settings/state use private permissions and atomic replacement; logs use codes/counts with bounded rotation.

## Compatibility and distribution

The corrected implementation completed one physical single-card scan on 2026-10-25 with an ES-C320W over USB, German ScanSmart 3.7.22 and macOS 27.0.1. This is limited acceptance; repeat cycles, longer sequences and the remaining manual cases are listed separately in VALIDATION.md. Other UI languages and changed layouts fail closed. Source build uses macOS AppleScript/JXA and system frameworks, with no third-party runtime. Developer tests use Node and Python. The local build is ad-hoc signed. A generally downloadable binary would need a stable Developer ID signature and notarization. Never run two helpers together.

## Integration contract

`core.js` declares global `AutoSaveCore` and CommonJS exports. `runtime.js` exposes `handleRequest(request)` returning JSON text. Both are loaded into the helper's own JavaScript OSA context, followed by a JSON-serialized request. No user values enter shell commands.

Snapshot keys: `foreground` boolean, `blocked` boolean, `processId` integer, `windowTitle` text, `captions` array of static/button strings, `fields` array of export combo-box values, `suffixLabels` array, `saveTargetCount` integer, `saveEnabled` boolean, `singlePage` boolean, `noJob` boolean. `noJob` is true only when ScanSmart is absent or has no content window, or the known German home caption is present without Choose/Save captions. Only the exact macOS `WindowSharingSessionButton` proxy window is excluded from content windows; real dialogs remain blocked. Background snapshots may verify files but never authorize actions.

Runtime requests: `startup`, `getSettings`, `setSettings` with `patch:{destination?,enabled?,dryRun?,pollIntervalMs?}`, `reset`, `tick` with snapshot, `observationError` with errorNumber, `canDispatch` with actionId and fresh snapshot, `reportAction` with actionId/success/errorCode/errorNumber. Responses always include `ok`, `settings`, `phase`, `status`, `errorCode` (nullable), `errorNumber` (nullable), and optional `action:{id,type,destination?}`. Types are `openSave`, `setDestination`, `save`. `tick` persists reservations before returning actions. `canDispatch` returns `allowed` and checks the latest snapshot/config/plan without consuming action. `reportAction` never equates dispatch with completed export. Transient read-only capture errors -1719/-1728 wait at most 10 seconds; a pending action instead pauses immediately. Permission errors -1743/-25211 pause as permission_denied. Runtime accepts optional `storageRoot` only for isolated developer test storage, and `now` only for deterministic tests. App never supplies these overrides.

Save metadata: captions contain `In Computereinstellungen speichern`; exactly one suffix label `_digits.jpg`/`.jpeg` or `.jpg`/`.jpeg`; fields contain exactly one absolute folder and one filename prefix; page count comes from unique `/ N` caption values (including `Ausgewähltes Bild: 1 / N`). If no counter is visible, count one requires the native single-page marker: known Save caption and no preview-navigation button. The core also requires exactly one unnumbered .jpg/.jpeg suffix; a numbered suffix without a readable count is always invalid. Prefix cannot contain path separators, NUL or be empty; reject ambiguous metadata and counter overflow. For no counter suffix require one page. Export metadata may finish loading during the first 10 seconds after opening the Save view; invalid metadata never authorizes Save. Expected paths are destination + prefix + counters + extension. Refuse preexisting targets. File verification requires JPEG SOI/EOI markers, a complete single-frame `public.jpeg` ImageIO source and frame, successful eager decoding with positive dimensions, and stable positive length across two observations. Invalid or incomplete images remain unconfirmed until the export timeout pauses automation without retrying Save.

Settings defaults: destination null, enabled false, dryRun false, pollIntervalMs 250 (integer 100..2000). Interval-only settings changes preserve state and pending actions. App name `ScanSmart AutoSave Beta`, ID `org.scansmart.autosave.beta`, version `0.1.0-beta.3-dev`, bundle build `3`. Storage `~/Library/Application Support/ScanSmart AutoSave/`, log in that directory. State phases include arming, ready, opening, setting_destination, verifying and paused. Timeouts use monotonic seconds (30 for transitions, 120 for export). Dry run displays planned actions but performs no setting or click.


## Timing controls

The native idle handler delegates to pollOnce and returns pollIntervalMs/1000;
disabled/paused mode returns two seconds. Native monotonic measurements cover
settings, capture, policy, action (fresh capture, guard, dispatch and ack), and
total work. Total excludes the post-poll gap and diagnostic persistence.
recordTiming accepts only five bounded numeric durations and an action enum;
runtime adds timestamp, phase/status and interval. getTimings returns at most
128 sanitized private records. Diagnostic errors report timingError without
resetting or pausing transaction state. Only active/error polls are recorded.
