# Toploader capture and orientation corrections

> **For agentic workers:** Use superpowers:executing-plans for inline implementation. Keep the existing feature branch and request a fresh review before installation.

**Goal:** Correct the failed physical Toploader acceptance: retain the complete holder, orient text-poor duplex cards, and retain source data on unsafe output dimensions.

**Spec:** `docs/superpowers/specs/2026-10-27-native-orientation-profiles-design.md`; the user's 29 October instruction authorizes continuing the local corrections and hardware tests. No GitHub publication is authorized.

## Evidence and implementation decisions

- ICA fixed-paper capture and native fixed-area capture cut off transparent trailing material. Native overscan additionally corrupts narrow windows and repeats trailing rows. Do not ship those configurations.
- The initial Epson/native probes succeeded with automatic area, laminated mode and positive crop margin. That initial choice of `laminatedPaperMode=1` was superseded by the controlled 2026-11-01 comparison below; retain the supported 0.20-inch margin for the acceptance build.
- Reuse the supervised native helper for transparent media. A single scan finishes after the first physical batch; continuous mode retains its existing Stop/timeout behavior. Epson-button start remains unchanged.
- Fixed dimensions describe an output canvas. Center the detected holder without scaling, trimming only the known capture margin. Reject a canvas smaller than the protected content. Keep raw originals until verified export; use capture/processing revision 2 for transparent jobs.
- OCR alone is insufficient for the energy card. Add an optional, local, upright reference image per profile, stored as a secure Vision revision-1 feature print rather than a card image or path. Match whole images and detected card rectangles at four rotations; require distance <=12 and a >=20% gap to the next rotation. These are implementation choices supported by the private probe, subject to broader negative/rotation checks.
- Strong OCR conflicts remain conflicts. A reliable reference can resolve an otherwise uncertain pair via the measured channel mapping, whichever physical face carries the reference. An unrelated image must retain the existing fixed fallback.

## Constraints and review focus

**2026-11-01 acceptance ruling:** Later repeated laminated-mode captures returned
no pages after transport. Changing only the transmitted native LAM field to OFF
delivered complete duplex images and clean close. The exact product helper and
installed build24 subsequently passed physical single-card, flipped/turned,
automatic reinsertion and Stop/PDF tests with laminated mode explicitly cleared
and checked. Full sensor area and the0.20in margin remain unchanged. A new upright
reference was selected only for the local Toploader profile; no algorithm or
confidence gate was relaxed. See the dated acceptance in `docs/VALIDATION.md` for
scope, the ordinary-card regression and remaining limits. This supersedes the
earlier mode choice, not the requirement to verify actual pixels and device close.

- Preserve existing profiles and schema-3 jobs that lack the new optional fields.
- Do not route ordinary cards through the new transparent-media path.
- A single transparent scan must not be presented/exported as a collection, and no-progress/parent-loss/Stop safeguards must remain bounded.
- Missing support, rejected driver settings, oversized reference data, unsafe framing and incomplete duplex output must not silently publish or delete originals.
- Keep all real scans, OCR output, archived feature prints and hardware reports outside Git.

## Task 1: Transparent capture and fixed output canvas

Files: `ScanProfile.swift`, `Settings.swift`, `NativeHelper.swift`, `ScanCoordinator.swift`, `EpsonFeedingWorker.m`, `ScanStorage.swift`, `PageProcessing.swift`, `VisionOrientation.swift`, `ProfilePanel.swift`; tests in `ProfileTests.swift`, `ProcessingTests.swift`, `HandoffTests.swift`, and `EpsonFeedingCallbacks.m`.

- [x] Add failing tests for transparent driver flags, button handoff to the native helper, ordinary one-card JPG/PDF export, stall protection, centered no-scale padding, rejection of content-truncating frames, and historical revision rejection.
- [x] Run the new tests and record their expected failures.
- [x] Add optional transparent-media profile configuration, checked native driver setup and one-batch completion. Stamp and validate revision 2. Implement centered framing with a protected margin of 60 pixels (0.20 inches at 300 dpi).
- [x] Run native tests and inspect the production diff.

## Task 2: Optional local orientation reference

Files: new `ReferenceOrientation.swift`; `ScanProfile.swift`, `PageProcessing.swift`, `ProfilePanel.swift`; tests in `OrientationTests.swift`, `ProfileTests.swift`, `ProcessingTests.swift`.

- [x] Add failing decision tests for correct/reversed channel matching, near ties, invalid distances, strong OCR conflict, unrelated images and reference persistence limits.
- [x] Implement secure feature-print creation/decoding, bounded four-rotation/rectangle analysis and conservative pair resolution. Add reference choose/remove controls to the existing profile editor.
- [x] Check all available private positive scans at four rotations and reject front/other-image negatives; do not reduce confidence gates merely to force a result.
- [x] Run the complete native suite.

## Task 3: Review, installation and physical acceptance

- [x] Update documentation and validation limits; run native, Node and package suites plus the release build.
- [x] Obtain an independent review of the new changes and fix material findings.
- [x] Back up the installed app and app data, install acceptance build24 (superseding20), and verify byte/signature equality. Configure the Toploader profile and its local upright reference through the UI.
- [x] Inspect actual Epson-button output for both complete borders, decoded sharpness and upright faces. Repeat upside down and with swapped physical faces; verify continuous PDF/Stop and a normal-card regression where practical.
- [x] Restore normal operating settings after acceptance and report remaining limits. Do not publish.
