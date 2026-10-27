# Native Mac downloads and repository identity

The user requested a matching repository name and a ready-to-download Mac app,
ideally installed through a DMG/installer instead of source compilation.
The existing repository was renamed to `DerFlash/epson-directscan`, preserving
its history, releases, issues and redirects. A fresh repository/archive would
lose continuity without helping installation; no old-name repository is created.

Distribution will use a read-only DMG containing `Epson DirectScan Beta.app`,
a standard `/Applications` link and concise installation/driver notes. A ZIP of
the same app is an alternative. The existing app is self-contained, so a PKG,
root installation scripts or automatic permission/login changes add no benefit.
The Epson driver remains separate. Source and checksums remain available.

Publish as v0.3.0-beta.2, build15: packaging/identity changes only, no scanner
behavior change. Keep bundle ID/app name/private data format stable. Download
names clearly say `macos-arm64`; Intel is not newly claimed as tested. Existing
user-local app copies should be quit and replaced at the same path to preserve
login registration; a second running copy must not be introduced.

The distribution build removes private debug build paths before signing.
Packaging refuses remaining home/temp build paths and must verify app/helper signatures, expected bundle ID/version and
arm64 architecture. It must refuse existing output and unexpected input,
preserve executable permissions, produce exact checksums and leave source app,
installed app and private user state untouched. Final DMG is mounted read-only
for inspection and a copied app is revalidated. Do not bundle the Epson driver,
real scans, settings, credentials or any Gatekeeper-disable/unquarantine script.

Release signing route: a clearly labelled ad-hoc beta with manual macOS
first-open confirmation. Developer-ID credentials are not part of this release. A public notarized
build requires Developer ID, hardened runtime, secure timestamps, notarization
and a stapled ticket. For this release, ad-hoc packages will be prepared, tested and published with
signing status explicit; do not claim notarization
or frictionless Gatekeeper acceptance. A paid account or new credential is not
created by this task. Hardened runtime signing would require a separate real
scanner retest because Epson framework loading is involved.

Acceptance: valid package/overwrite/input tests; native and legacy suites; DMG
integrity/mount/content/symlink/signature checks; all executable code unchanged
apart from signing/metadata; download after upload matches checksums. Publish
only the signing status actually achieved and include first-launch/update notes.
