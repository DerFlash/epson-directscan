# Complete profile controls

The accepted UI request is to edit every existing configurable scan choice together in the AppKit profile editor and make menu quick switches visibly belong to the active profile. Keep the current storage, model and capture behavior.

The editor contains the destination, JPG/PDF preference, duplex, collection mode, existing timeouts (30/60/120/300 seconds or unlimited), crop/deskew and the existing geometry, transparent-holder, orientation and reference controls. Collection mode displays the effective collection PDF and disables its per-sheet format choice. Resolution and color remain a read-only `300 dpi · Farbe` capability.

Existing named profiles retain their IDs, reference data and calibration mappings. Edits stay local until Save invokes the existing callback. Cancel changes nothing. The legacy entry is editable too, using automatic geometry and only unchanged/Epson orientation; saving it updates legacy settings without creating a named profile.

Duplicate profile names and names matching built-in editor choices retain separate identity-bearing menu items, with display-only qualifiers where needed. Destination paths are literal values, including valid trailing spaces; storage remains responsible for validation.

Disabled correction controls show actual effective values: fixed opaque frames disable crop/deskew; transparent holders force driver crop on and deskew off. Disabled controls preserve the raw saved preferences. The form scrolls independently of the footer buttons.

Implementation choice: extend the existing programmatic AppKit form and existing snapshot methods rather than introducing another editor, storage object or model. Menu switches receive an explicit active-profile heading, including the folder action; named profiles get supported orientation choices.

Only ProfilePanel.swift, AppDelegate.swift, focused UI tests and these UI documents change. No capture/controller/helper changes, installation, commits or publication are part of this delegated implementation.
