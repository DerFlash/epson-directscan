# Native Mac Download Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for inline implementation. Steps use checkbox syntax.

**Goal:** Deliver correctly named GitHub releases with a finished Apple-Silicon Mac app and DMG.
**Architecture:** Package the existing signed app, without changing capture logic or private data. Keep repository history through rename.
**Tech Stack:** Existing Swift app, macOS codesign/ditto/hdiutil, shell packaging, Python verification.
**Spec:** `docs/superpowers/specs/2026-10-27-native-downloads-design.md`

## Global Constraints

- No bundled Epson software or private data; no credential export or security bypass.
- Keep bundle ID/app name and existing installed app unchanged.
- arm64 beta only, version0.3.0-beta.2/build15; signing status must be accurate.
- Refuse overwrite and invalid source; verify all executable signatures and package contents.

## Review Focus

- A bad or wrong app must not be packaged under the trusted download name.
- Existing output/input files must not be destroyed by packaging or cleanup.
- DMG/ZIP must preserve all executable bytes, permissions and signatures.
- Existing user-local app and login entry must not be duplicated by update instructions.
- An ad-hoc build must never be described as Developer-ID signed/notarized.

### Task 1: Tested package creation

**Files:** Create `scripts/package-native.sh` and `tests/package_native_test.py`.
**Interfaces:** `package-native.sh [--app ABSOLUTE_APP] [--output ABSOLUTE_NEW_DIRECTORY] [--require-notarized]`. Default input is `build/Epson DirectScan Beta.app`; output defaults to `dist/epson-directscan-VERSION-macos-arm64`. Produces same-name `.dmg`, app `.zip`, `SHA256SUMS` and `PACKAGE-INFO.json`. Reject a non-Mac host, symlink input, wrong bundle ID, incomplete helpers, invalid signatures, non-arm64 executables and existing output.

- [ ] Add behavior tests for successful ZIP/DMG/checksum output, wrong bundle rejection and overwrite refusal.
- [ ] Run new tests against missing packaging behavior and inspect RED failures.
- [ ] Implement `scripts/package-native.sh` for an existing verified app; use a private staging directory and hdiutil read-only image.
- [ ] Run package tests GREEN; inspect mounted DMG and copied app signatures. No scan is triggered.

### Task 2: Release integration

**Files:** Update native `Info.plist`, `README.md`, `docs/NATIVE.de.md`, `SECURITY.md`, `CHANGELOG.md`, `.github/workflows/check.yml`, release notes and validation. No capture/storage/helper source changes.
**Interfaces:** Uses Task1 packages built from the release-labelled app; source ZIP and checksums are added for the public GitHub release. Existing user installation remains untouched.

- [ ] Promote metadata to beta2/build15, update active canonical URLs and native-first download/update/signing instructions.
- [ ] Run native/legacy checks, build, package and compare executable code with the hardware-tested version.
- [ ] Independent final release review, remote CI, source/package privacy and checksum verification.
- [ ] Publish actual achieved signing status and verified DMG/app/source downloads; read back the GitHub result.

The user chose an ad-hoc beta with manual macOS first-open confirmation. Notarization is explicitly outside this release; do not request credentials or claim Gatekeeper approval.
