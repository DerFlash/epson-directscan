# Profile Editor Controls Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans task by task. Keep the implementation uncommitted for the independent reviewer.

**Goal:** Edit existing profile settings together and label quick switches with their active profile.

**Architecture:** Keep a local editor snapshot and reuse ProfileScanSettings, selectProfile, saveProfile and rememberActiveProfileSettings. Extend the current AppKit form and save callback; the footer remains outside its scroll view.

**Tech Stack:** Swift, AppKit, Swift Testing.

**Spec:** docs/superpowers/specs/2026-11-18-profile-editor-controls-design.md

## Global Constraints

- No settings/model/capture/controller/helper behavior changes.
- Keep named identities, references and calibration mappings.
- Cancel and draft edits have no persistence side effects.
- Legacy saves create no profile and support automatic geometry only.
- No installation, commit, push or merge by this implementer.

## Review Focus

- Named profiles with saved references keep those values after editing output controls.
- Collection mode preserves and later restores its per-sheet format preference.
- Fixed frames and transparent holders show effective corrections without overwriting raw preferences.
- Selecting legacy while a named profile is active does not overwrite named geometry or identity.
- Save/Cancel remain outside scrolling content on smaller screens.

### Task 1: Complete the editor

**Files:** native/Sources/EpsonDirectScan/ProfilePanel.swift; native/Tests/DirectScanCoreTests/ProfilePanelTests.swift

**Interfaces:** Keep `init(settings: ScanSettings, completion: @escaping (ScanSettings?) -> Bool)` and the existing save callback. Identify real controls with `profile.*` AppKit identifiers.

- [x] Write behavioral tests for saving output choices and geometry, Cancel, collection format restoration, legacy save, disabled correction preferences and footer access.
- [x] Run focused tests and observe missing-control failures before implementation.
- [x] Add the controls, draft-only changes, supported legacy editing and effective-state presentation.
- [x] Run focused tests, then `./scripts/test-native.sh`; expect zero failures.

### Task 2: Active-profile quick switches

**Files:** native/Sources/EpsonDirectScan/AppDelegate.swift; native/Tests/DirectScanCoreTests/ProfileMenuTests.swift

**Interfaces:** Existing menu persistence uses `persist(_:)`; named orientation updates use `saveProfile(_:)` and the same persistence path.

- [x] Put folder and scan choices under `Schnellschalter für „<name>“`.
- [x] Show effective corrections, disabling fixed/holder choices that are forced by the capture path.
- [x] Replace the disabled named-profile legacy rotation toggle with valid orientation choices; preserve unsupported historical choices until the user selects a supported mode.
- [x] Verify the full native suite and inspect the UI-only diff. Leave review and integration to the parent agent.

## Verification and independent review

- Initial RED: seven ProfilePanel tests failed on missing controls; existing suite passed.
- Menu RED: three ProfileMenu tests failed on missing quick-switch menu items; seven editor tests passed.
- Independent review identified two UI issues. `duplicateAndLegacyNamedProfilesRemainSelectableByIdentity` reproduced entry loss and wrong initial selection before explicit NSMenuItem construction/UUID selection fixed it. `unchangedDestinationWithTrailingSpaceKeepsExactFolder` reproduced routing to an existing shortened sibling before literal-path handling fixed it. Both followed RED→GREEN.
- Final focused run: 13 tests in 3 suites passed (12 UI/menu cases plus the parent's new zero-page Handoff case).
- Final `./scripts/test-native.sh`: callback harness succeeded; 154 tests in 20 suites passed. The timing-sensitive HelperProcess suite passed, including its distinct arm/finish signal case.
- Final implementation remains uncommitted. No CUA, installation, scanner/controller/helper edits, commit, push or merge were performed by this UI implementer.
