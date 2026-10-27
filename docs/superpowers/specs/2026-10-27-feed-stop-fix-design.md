# Issue #3: failed pickup and empty Stop

The user explicitly requested implementation, local installation and a device
retest of [issue #3](https://github.com/DerFlash/epson-scansmart-autosave/issues/3).
This is a correction within the existing native app, on the existing branch.

Observed root cause: ICA reports completion without an error or any pages after
physical Stop. The controller sends the empty manifest to the nonempty export
path, which deliberately rejects it. The worker then emits generic error -201.

Keep the existing ICA/isolated-worker architecture. Treat a successful empty
completion and the documented ICA cancellation error as an empty result only
when no complete or partial image files exist. Validate and discard the metadata
only after the scanner session is confirmed closed. Only the parent may rearm,
after both the close event and a successful process exit. Preserve unknown
files, incomplete duplex pairs, genuine device errors and unconfirmed releases.

Add a 15-second no-completed-page watchdog to normal scanning, resetting on each
validated page; request cancellation and allow 12 seconds for acknowledgement.
The continuous path uses the same limit only inside an active batch, never
while waiting for more paper. It requests normal collection finish and retains
existing page safety rules. Neither path retries capture automatically.

Show a persistent, nonfatal notice after an empty result/no-progress finish,
alongside readiness for a fresh physical Start. Actual transport/USB errors and
partial ordinary scans remain errors with retained data. Do not infer physical
Stop from an unrelated error code. Keep settings, output formats and login item.

Alternatives: ignoring all errors would hide real failures; shortening the
whole-session deadline would break continuous waiting and long valid batches.
The targeted completion/progress fix addresses the observed failure directly.
The 15-second limit is an implementation choice for the current card workflow;
hardware timing is part of acceptance, not an assumed guarantee.

Acceptance: fake-device tests exercise actual controller/storage state and
parent handoff ordering, full existing suites/build pass, then install with a
backup and test empty Stop, no-progress cancellation and a subsequent valid
card on the ES-C320W. Destructive jam/USB tests are not required on valuable
media; any unperformed hardware cases remain explicitly unverified.
