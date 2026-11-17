# Receipt Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein Profilwechsel stellt die vollständigen Ablagevorgaben für Belege und Karten wieder her.

**Architecture:** Optionale `ProfileScanSettings` in `ScanProfile` und ein entsprechender Legacy-Speicher in `ScanSettings`; `selectProfile(_:)` sichert und lädt diese Vorgaben atomar. Der bestehende Profil-Editor erhält Ordner/PDF-Auswahl und „Neues Belegprofil“.

**Tech Stack:** Swift, AppKit, Swift Testing; vorhandene native Buildskripte.

**Spec:** docs/superpowers/specs/2026-11-17-receipt-profiles-design.md

## Global Constraints

- Bestehende Schema-3-Einstellungen, Profil-IDs, Referenzen und Aufträge erhalten.
- Keine Änderungen an Treibern, Kartenmaßen, OCR/PDF-Inhalten oder Einzugslogik.
- Kein automatischer Hardware-Scan zur Prüfung.
- Installation am bisherigen Pfad mit vorheriger Sicherung.

## Review Focus

- Wechsel Belege → Karten nach App-Neustart stellt Ordner und JPG wieder her.
- Menüänderungen werden beim Verlassen des Profils gespeichert.
- Fehlende Vorgaben alter Profile übernehmen aktuelle Werte ohne Verlust.
- Unbekannte/ungültige Zielprofile lassen aktive Einstellungen unverändert.
- Löschen des aktiven Profils kehrt zu den gespeicherten bisherigen Einstellungen zurück.

### Task 1: Profilvorgaben, Editor und lokale Einrichtung

**Files:**
- Create: `native/Sources/DirectScanCore/ProfileScanSettings.swift`
- Create: `native/Tests/DirectScanCoreTests/ProfileSettingsTests.swift`
- Modify: `native/Sources/DirectScanCore/Settings.swift`
- Modify: `native/Sources/DirectScanCore/ScanProfile.swift`
- Modify: `native/Sources/EpsonDirectScan/AppDelegate.swift`
- Modify: `native/Sources/EpsonDirectScan/ProfilePanel.swift`
- Modify: `native/Resources/Info.plist`, `docs/NATIVE.de.md`, `CHANGELOG.md`

**Interfaces:**
- `ProfileScanSettings(settings: ScanSettings)` erfasst die Ablage-/Scanvorgaben.
- `ScanSettings.selectProfile(_ id: UUID?) throws` sichert und lädt Profilvorgaben.
- `ScanSettings.rememberActiveProfileSettings()` synchronisiert den aktiven Speicher.
- `ScanProfile.receipts(destination: String?) -> ScanProfile` liefert das automatische PDF-Belegprofil.

- [x] Tests zuerst schreiben: Karten/Belege-Rundreise mit Neustart und Menüänderungen, Legacy-Rückkehr, alte Profile, ungültige Ziele ohne Mutation und echter PDF-Export mit gewähltem Profil.
- [x] Tests ausführen und das Fehlen der neuen Profilvorgaben bestätigen.
- [x] Minimale optionale Speicherwerte und Umschaltfunktionen implementieren; Editor und Menüpfade anbinden, aktives Profil vor dem Löschen verlassen.
- [x] Vollständige native Suite und Release-Build ausführen. Expected: alle Tests bestanden, signierte App gebaut.
- [x] Änderung unabhängig geprüft, Befunde behoben und PR-Text vorbereitet. Externes Hochladen wurde von der automatischen Freigabe mangels ausdrücklicher Nutzerfreigabe abgelehnt; keine Veröffentlichung und kein Merge erfolgt.
- [x] Bisherige App/Einstellungen sichern, aktualisierte App installieren, Belegprofil mit bestätigtem Ordner hinzufügen und Profilwechsel ohne Hardware-Scan prüfen.
