# v0.1.0-beta.1 validation

This is a source beta. Automated checks establish the behavior below; they do
not establish real scanner or Epson UI compatibility for the newly packaged app.

| Check | Result |
|---|---|
| Pure policy and native-event guard tests | 17 passed; input posting is substituted |
| AppleScript bridge/geometry/status and real Foundation/ImageIO tests | 19 passed; isolated temporary storage, no GUI input |
| Clean macOS app build and strict local signature verification | Passed |
| Temporary installation, existing-target refusal and explicit replacement | Passed, including a destination containing spaces; never launched |
| Shell syntax and whitespace checks | Passed |
| Independent code review | False JPEG success fixed with complete native decoding; regression cases included |
| GitHub-hosted CI | Workflow provided; not run on GitHub before publication |
| New beta end-to-end hardware acceptance | Pending |

The test fixture is a synthetic 2 × 2 white image. Invalid-image cases include a
two-byte JPEG header, an interrupted real JPEG, marker-wrapped garbage and
non-image data. None may report success or trigger a repeated Save.

Only the predecessor has observed hardware evidence: ES-C320W over USB, German
ScanSmart 3.7.22 and macOS 27.0.1. The new folder setter, app identity and permissions
need acceptance with a real scanner. The compiled beta was not launched alongside
an existing helper during preparation.

Before marking a device/version combination as tested:

1. Quit all other scan helpers. Install one beta copy and grant that copy its own
   macOS permissions. Choose an empty test destination and enable the helper.
2. Finish/cancel any pending export and let it observe ScanSmart's normal start
   screen. Scan a harmless sample with the physical scanner button and leave the
   Mac untouched. Confirm the exact expected JPG count, readable images, correct
   folder and successful app status.
3. Repeat twice to check the next scan rearms. Change the destination through the
   app, rearm from the start screen and confirm only the new folder receives files.
4. Test cancelling before Save, disabling the helper, dry run and a manually
   handled error dialog. Check that none creates an unintended file or click.
5. Test an existing expected filename and an unavailable destination. The helper
   must pause. Inspect output, resolve the cause, reset, and use a fresh scan.
6. Restart the helper while an export is pending. It must wait for you to finish
   or cancel it rather than exporting that uncertain job automatically.

Record the exact macOS, ScanSmart, scanner and connection versions with results.
Do not publish real scans, private paths or unredacted state files as evidence.
