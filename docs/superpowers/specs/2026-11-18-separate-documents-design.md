# Separate documents per scan profile

The user requested implementation of the previously discussed local Vision/Core Image workflow as an option per named scan profile. A carrier sheet has been ordered; installed-app hardware acceptance with that sheet cannot happen yet.

## Behavior

- Add “Separate Dokumente erkennen” in the profile editor and a labelled shortcut for the active named profile. Default off; old settings and pending jobs remain readable. Preserve all existing profiles/references.
- When enabled, analyze the complete captured image with Vision rectangle detection, remove obvious sleeve/image-border and nested duplicates, and reject overlapping/invalid geometry conservatively.
- Correct each accepted quadrilateral with Core Image, orient each resulting document independently using the existing text-orientation decision, and publish one file/PDF per document according to the profile output choice.
- Keep a private copy of the full source job after successful split publication. Do not add full-source duplicates to the user's receipt inbox.
- If boundaries cannot be separated confidently, retain the full source rather than silently discard content. Surface a clear notice and provide full-page recovery.
- Stop/cancel, parent/session leases, source validation, export receipts, exclusive publication and reentrant recovery remain effective. Bound image sizes, candidate counts and analysis time.
- Existing ordinary/card/toploader jobs retain their current pipeline and output layout.

## Approach

Use the already discussed Apple Vision rectangle detector plus Core Image perspective correction. Keep detector/filter/crop in a focused new file. Add a separate one-to-many processing journal rather than weakening the current one-to-one page-processing verification. Reuse verified output publication and PDF generation.

An external model or cloud service would add dependencies and transmit private receipts; neither is needed. A fixed number of rectangular zones would not recognize arbitrary receipt placement and does not meet the requested detection behavior.

## Duplex behavior

The user confirmed that duplex must associate the correct backs with the correct fronts. The existing per-profile duplex switch controls both paths. Off exports each front separately; on pairs front/back crops only if geometric correspondence is unambiguous across the possible page-flip transforms. If several transforms imply different equally plausible pairings, retain the original job and expose full-page recovery. Never guess a side association. Preserve the installed profile's current setting.

## Validation

Real Vision tests on synthetic multi-document images; geometry tests for sleeve borders, nested duplicate frames, overlap, invalid/out-of-range corners and excessive candidates; real pixel crops and independent rotations; real multi-PDF publication, retries/cancellation/collision, full-source retention and old jobs; profile persistence/editor/menu; full native suite and signed release build, independent review, PR checks and merge/install under the user's standing authorization.
